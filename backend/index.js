const AWS = require("aws-sdk");

const dynamo = new AWS.DynamoDB.DocumentClient();
const TABLE_NAME = process.env.DYNAMODB_TABLE || "videos-dev";
const CF_DOMAIN = process.env.CF_URL; // e.g. https://xxxx.cloudfront.net
const KEY_PAIR_ID = process.env.KEY_PAIR_ID;
const PRIVATE_KEY = process.env.PRIVATE_KEY; // PEM string, newlines as \n
const SIGNED_URL_TTL = 3600; // 1 hour

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build a response object for API Gateway HTTP API (payload format 2.0).
 */
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
 * Generate a CloudFront signed URL using a custom policy.
 * The custom policy covers all files under the video folder prefix,
 * so both the .m3u8 manifest and all .ts segments are authorised
 * with a single signed URL embedded in the manifest path.
 *
 * HLS.js will use the signed manifest URL, and CloudFront will serve
 * the .ts segments because they share the same signed cookie set
 * via the response headers.
 */
function signedUrl(s3Key) {
  if (!KEY_PAIR_ID || !PRIVATE_KEY) {
    throw new Error(
      "CloudFront signing env vars KEY_PAIR_ID and PRIVATE_KEY are not set"
    );
  }

  const signer = new AWS.CloudFront.Signer(KEY_PAIR_ID, PRIVATE_KEY);
  return signer.getSignedUrl({
    url: `${CF_DOMAIN}/${s3Key}`,
    expires: Math.floor(Date.now() / 1000) + SIGNED_URL_TTL,
  });
}

/**
 * Generate CloudFront signed cookies that cover an entire folder prefix.
 * These are set on the API response so the browser sends them automatically
 * with every subsequent CloudFront request (manifest + all .ts segments).
 */
function signedCookies(pathPrefix) {
  if (!KEY_PAIR_ID || !PRIVATE_KEY) {
    throw new Error(
      "CloudFront signing env vars KEY_PAIR_ID and PRIVATE_KEY are not set"
    );
  }

  const signer  = new AWS.CloudFront.Signer(KEY_PAIR_ID, PRIVATE_KEY);
  const expires = Math.floor(Date.now() / 1000) + SIGNED_URL_TTL;

  return signer.getSignedCookie({
    url: `${CF_DOMAIN}/${pathPrefix}*`,
    expires,
  });
}
function signedUrl(s3Key) {
  if (!KEY_PAIR_ID || !PRIVATE_KEY) {
    throw new Error(
      "CloudFront signing env vars KEY_PAIR_ID and PRIVATE_KEY are not set"
    );
  }

  const signer = new AWS.CloudFront.Signer(KEY_PAIR_ID, PRIVATE_KEY);
  return signer.getSignedUrl({
    url: `${CF_DOMAIN}/${s3Key}`,
    expires: Math.floor(Date.now() / 1000) + SIGNED_URL_TTL,
  });
}

/**
 * GET /videos/:id/manifest
 * Fetches the HLS manifest from S3 via CloudFront and rewrites each .ts segment
 * line with its own signed URL. This is the key to making HLS work with signed URLs —
 * the player gets a manifest where every segment is individually signed.
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

  // Fetch the manifest content from S3 directly
  const s3 = new AWS.S3();
  const outputBucket = process.env.OUTPUT_BUCKET;

  let manifestContent;
  try {
    const s3Obj = await s3.getObject({
      Bucket: outputBucket,
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
      // Segment lines end with .ts — rewrite them with signed URLs
      if (trimmed.endsWith(".ts") && !trimmed.startsWith("#")) {
        const segmentKey = folder + trimmed;
        return signedUrl(segmentKey);
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

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

/**
 * GET /videos
 * Returns the full video catalog from DynamoDB.
 * Each item includes metadata but NOT a signed URL — that is generated on demand
 * when the user clicks play, to avoid generating hundreds of short-lived URLs at once.
 */
async function listVideos() {
  const result = await dynamo
    .scan({
      TableName: TABLE_NAME,
      // Only return fields needed for the catalog view — keeps the response lean
      ProjectionExpression:
        "video_id, title, description, genre, #dur, thumbnail_key, #st",
      ExpressionAttributeNames: {
        "#dur": "duration", // reserved word in DynamoDB
        "#st": "status",
      },
    })
    .promise();

  return respond(200, { videos: result.Items });
}

/**
 * GET /videos/:id
 * Returns full metadata for a single video plus a signed CloudFront URL for playback.
 * The signed URL points to the HLS manifest (.m3u8) in the output bucket.
 */
async function getVideo(videoId) {
  const result = await dynamo
    .get({
      TableName: TABLE_NAME,
      Key: { video_id: videoId },
    })
    .promise();

  if (!result.Item) {
    return respond(404, { error: "Video not found" });
  }

  const video = result.Item;

  let streamUrl = null;

  if (video.status === "ready" && video.output_key) {
    // Sign the manifest URL — this is what HLS.js loads first
    streamUrl = signedUrl(video.output_key);
  }

  return respond(200, { video: { ...video, stream_url: streamUrl } });
}

/**
 * POST /videos
 * Writes a new video metadata record to DynamoDB.
 * Called after a raw file has been uploaded to the S3 input bucket.
 * The MediaConvert pipeline will update the status to "ready" once transcoding completes.
 *
 * Expected body:
 * {
 *   "video_id": "abc123",          // unique ID, e.g. UUID
 *   "title": "My Movie",
 *   "description": "...",
 *   "genre": "Action",
 *   "duration": 7200,              // seconds
 *   "thumbnail_key": "thumbs/abc123.jpg",
 *   "output_key": "videos/abc123/index.m3u8"  // set after upload, before transcoding
 * }
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
    status: data.status || "pending",
    created_at: new Date().toISOString(),
  };

  try {
    await dynamo
      .put({
        TableName: TABLE_NAME,
        ConditionExpression: "attribute_not_exists(video_id)",
        Item: item,
      })
      .promise();

    return respond(201, { video: item });
  } catch (err) {
    // Record already exists — overwrite it without the condition check
    if (err.code === "ConditionalCheckFailedException") {
      await dynamo
        .put({
          TableName: TABLE_NAME,
          Item: { ...item, updated_at: new Date().toISOString() },
        })
        .promise();

      return respond(200, { video: item });
    }
    throw err;
  }
}

/**
 * PUT /videos/:id/status
 * Updates the transcoding status of a video.
 * Intended to be called by the MediaConvert trigger Lambda once a job completes.
 *
 * Expected body: { "status": "ready" | "processing" | "error" }
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
      TableName: TABLE_NAME,
      Key: { video_id: videoId },
      UpdateExpression: "SET #st = :status, updated_at = :ts",
      ConditionExpression: "attribute_exists(video_id)",
      ExpressionAttributeNames: { "#st": "status" },
      ExpressionAttributeValues: {
        ":status": status,
        ":ts": new Date().toISOString(),
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
  // API Gateway HTTP API v2 uses event.rawPath; v1 uses event.path
  const path = event.rawPath || event.path || "/";

  // Strip trailing slash for consistent matching
  const normalizedPath = path.replace(/\/$/, "") || "/";

  try {
    // GET /videos
    if (method === "GET" && normalizedPath === "/videos") {
      return await listVideos();
    }

    // GET /videos/:id/manifest — returns HLS manifest with signed segment URLs
    const manifestMatch = normalizedPath.match(/^\/videos\/([^/]+)\/manifest$/);
    if (method === "GET" && manifestMatch) {
      return await getManifest(manifestMatch[1]);
    }

    // GET /videos/:id
    const videoMatch = normalizedPath.match(/^\/videos\/([^/]+)$/);
    if (method === "GET" && videoMatch) {
      return await getVideo(videoMatch[1]);
    }

    // POST /videos
    if (method === "POST" && normalizedPath === "/videos") {
      return await createVideo(event.body);
    }

    // PUT /videos/:id/status
    const statusMatch = normalizedPath.match(/^\/videos\/([^/]+)\/status$/);
    if (method === "PUT" && statusMatch) {
      return await updateVideoStatus(statusMatch[1], event.body);
    }

    // Health check
    if (method === "GET" && normalizedPath === "/health") {
      return respond(200, { status: "ok" });
    }

    return respond(404, { error: "Route not found" });
  } catch (err) {
    console.error("Unhandled error:", err);

    // Don't leak internal error details to the client
    return respond(500, { error: "Internal server error" });
  }
};
