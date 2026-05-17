const AWS = require("aws-sdk");

const dynamo = new AWS.DynamoDB.DocumentClient();
const TABLE_NAME   = process.env.DYNAMODB_TABLE || "videos-dev";
const CF_DOMAIN    = process.env.CF_URL;
const KEY_PAIR_ID  = process.env.KEY_PAIR_ID;
const PRIVATE_KEY  = process.env.PRIVATE_KEY;
const OUTPUT_BUCKET = process.env.OUTPUT_BUCKET;
const SIGNED_URL_TTL = 3600; // 1 hour

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function respond(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type,Authorization",
    },
    body: JSON.stringify(body),
  };
}

/**
 * Generate a signed CloudFront URL for a single S3 key.
 */
function signedUrl(s3Key) {
  if (!KEY_PAIR_ID || !PRIVATE_KEY) {
    throw new Error("CloudFront signing env vars KEY_PAIR_ID and PRIVATE_KEY are not set");
  }
  const signer = new AWS.CloudFront.Signer(KEY_PAIR_ID, PRIVATE_KEY);
  return signer.getSignedUrl({
    url:     `${CF_DOMAIN}/${s3Key}`,
    expires: Math.floor(Date.now() / 1000) + SIGNED_URL_TTL,
  });
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

/**
 * GET /videos
 * Returns the catalog from DynamoDB — no signed URLs, just metadata.
 */
async function listVideos() {
  const result = await dynamo
    .scan({
      TableName: TABLE_NAME,
      ProjectionExpression: "video_id, title, description, genre, #dur, thumbnail_key, #st",
      ExpressionAttributeNames: {
        "#dur": "duration",
        "#st":  "status",
      },
    })
    .promise();

  return respond(200, { videos: result.Items });
}

/**
 * GET /videos/:id
 * Returns full metadata + a signed CloudFront URL for the manifest.
 */
async function getVideo(videoId) {
  const result = await dynamo
    .get({ TableName: TABLE_NAME, Key: { video_id: videoId } })
    .promise();

  if (!result.Item) {
    return respond(404, { error: "Video not found" });
  }

  const video = result.Item;
  let streamUrl = null;

  if (video.status === "ready" && video.output_key) {
    streamUrl = signedUrl(video.output_key);
  }

  return respond(200, { video: { ...video, stream_url: streamUrl } });
}

/**
 * GET /videos/:id/manifest
 * Fetches the HLS manifest from S3 and rewrites every .ts segment line
 * with its own signed CloudFront URL so HLS.js can fetch all segments.
 */
async function getManifest(videoId) {
  const result = await dynamo
    .get({ TableName: TABLE_NAME, Key: { video_id: videoId } })
    .promise();

  if (!result.Item || !result.Item.output_key) {
    return respond(404, { error: "Video not found" });
  }

  const outputKey = result.Item.output_key;
  const folder    = outputKey.substring(0, outputKey.lastIndexOf("/") + 1);

  // Fetch the manifest directly from S3
  const s3 = new AWS.S3();
  let manifestContent;
  try {
    const s3Obj = await s3.getObject({
      Bucket: OUTPUT_BUCKET,
      Key:    outputKey,
    }).promise();
    manifestContent = s3Obj.Body.toString("utf-8");
  } catch (err) {
    console.error("Failed to fetch manifest from S3:", err);
    return respond(500, { error: "Could not fetch manifest" });
  }

  // Rewrite each .ts segment line with a signed CloudFront URL
  const rewritten = manifestContent
    .split("\n")
    .map((line) => {
      const trimmed = line.trim();
      if (trimmed.endsWith(".ts") && !trimmed.startsWith("#")) {
        return signedUrl(folder + trimmed);
      }
      return line;
    })
    .join("\n");

  return {
    statusCode: 200,
    headers: {
      "Content-Type":                "application/vnd.apple.mpegurl",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control":               "no-cache",
    },
    body: rewritten,
  };
}

/**
 * POST /videos
 * Creates or overwrites a video metadata record in DynamoDB.
 */
async function createVideo(body) {
  let data;
  try {
    data = typeof body === "string" ? JSON.parse(body) : body;
  } catch {
    return respond(400, { error: "Invalid JSON body" });
  }

  const { video_id, title } = data;
  if (!video_id || !title) {
    return respond(400, { error: "video_id and title are required" });
  }

  const item = {
    ...data,
    status:     data.status || "pending",
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    await dynamo
      .put({
        TableName:           TABLE_NAME,
        ConditionExpression: "attribute_not_exists(video_id)",
        Item:                item,
      })
      .promise();
    return respond(201, { video: item });
  } catch (err) {
    if (err.code === "ConditionalCheckFailedException") {
      // Record exists — overwrite it
      await dynamo.put({ TableName: TABLE_NAME, Item: item }).promise();
      return respond(200, { video: item });
    }
    throw err;
  }
}

/**
 * PUT /videos/:id/status
 * Updates the transcoding status of a video.
 */
async function updateVideoStatus(videoId, body) {
  let data;
  try {
    data = typeof body === "string" ? JSON.parse(body) : body;
  } catch {
    return respond(400, { error: "Invalid JSON body" });
  }

  const { status } = data;
  if (!status) {
    return respond(400, { error: "status is required" });
  }

  const result = await dynamo
    .update({
      TableName:                 TABLE_NAME,
      Key:                       { video_id: videoId },
      UpdateExpression:          "SET #st = :status, updated_at = :ts",
      ConditionExpression:       "attribute_exists(video_id)",
      ExpressionAttributeNames:  { "#st": "status" },
      ExpressionAttributeValues: {
        ":status": status,
        ":ts":     new Date().toISOString(),
      },
      ReturnValues: "ALL_NEW",
    })
    .promise();

  return respond(200, { video: result.Attributes });
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

exports.handler = async (event) => {
  const method = event.requestContext?.http?.method || event.httpMethod || "GET";
  const path   = event.rawPath || event.path || "/";
  const normalizedPath = path.replace(/\/$/, "") || "/";

  try {
    if (method === "GET" && normalizedPath === "/health") {
      return respond(200, { status: "ok" });
    }

    if (method === "GET" && normalizedPath === "/videos") {
      return await listVideos();
    }

    const manifestMatch = normalizedPath.match(/^\/videos\/([^/]+)\/manifest$/);
    if (method === "GET" && manifestMatch) {
      return await getManifest(manifestMatch[1]);
    }

    const videoMatch = normalizedPath.match(/^\/videos\/([^/]+)$/);
    if (method === "GET" && videoMatch) {
      return await getVideo(videoMatch[1]);
    }

    if (method === "POST" && normalizedPath === "/videos") {
      return await createVideo(event.body);
    }

    const statusMatch = normalizedPath.match(/^\/videos\/([^/]+)\/status$/);
    if (method === "PUT" && statusMatch) {
      return await updateVideoStatus(statusMatch[1], event.body);
    }

    return respond(404, { error: "Route not found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return respond(500, { error: "Internal server error" });
  }
};
