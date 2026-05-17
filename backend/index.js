const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  ScanCommand,
  GetCommand,
  PutCommand,
  UpdateCommand,
} = require("@aws-sdk/lib-dynamodb");
const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/cloudfront-signer");

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3     = new S3Client({});

const TABLE_NAME     = process.env.DYNAMODB_TABLE || "videos-dev";
const CF_DOMAIN      = process.env.CF_URL;
const KEY_PAIR_ID    = process.env.KEY_PAIR_ID;
const PRIVATE_KEY    = process.env.PRIVATE_KEY;
const OUTPUT_BUCKET  = process.env.OUTPUT_BUCKET;
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

// Generate a signed CloudFront URL using SDK v3 cloudfront-signer
function signedUrl(s3Key) {
  if (!KEY_PAIR_ID || !PRIVATE_KEY) {
    throw new Error("CloudFront signing env vars KEY_PAIR_ID and PRIVATE_KEY are not set");
  }
  return getSignedUrl({
    url:               `${CF_DOMAIN}/${s3Key}`,
    keyPairId:         KEY_PAIR_ID,
    privateKey:        PRIVATE_KEY,
    dateLessThan:      new Date(Date.now() + SIGNED_URL_TTL * 1000).toISOString(),
  });
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

// GET /videos — returns catalog from DynamoDB, no signed URLs
async function listVideos() {
  const result = await dynamo.send(new ScanCommand({
    TableName:                TABLE_NAME,
    ProjectionExpression:     "video_id, title, description, genre, #dur, thumbnail_key, #st",
    ExpressionAttributeNames: { "#dur": "duration", "#st": "status" },
  }));
  return respond(200, { videos: result.Items });
}

// GET /videos/:id — returns metadata + signed CloudFront URL
async function getVideo(videoId) {
  const result = await dynamo.send(new GetCommand({
    TableName: TABLE_NAME,
    Key:       { video_id: videoId },
  }));

  if (!result.Item) return respond(404, { error: "Video not found" });

  const video = result.Item;
  let streamUrl = null;
  if (video.status === "ready" && video.output_key) {
    const encodedKey = video.output_key.split("/").map((seg) => encodeURIComponent(seg)).join("/");
    streamUrl = signedUrl(encodedKey);
  }

  return respond(200, { video: { ...video, stream_url: streamUrl } });
}

// GET /videos/:id/manifest — fetches HLS manifest from S3 and rewrites
// every .ts segment line with a signed CloudFront URL for HLS.js
async function getManifest(videoId) {
  const result = await dynamo.send(new GetCommand({
    TableName: TABLE_NAME,
    Key:       { video_id: videoId },
  }));

  if (!result.Item || !result.Item.output_key) {
    return respond(404, { error: "Video not found" });
  }

  const outputKey = result.Item.output_key;
  const folder    = outputKey.substring(0, outputKey.lastIndexOf("/") + 1);

  // Fetch manifest from S3 using raw key (S3 API needs unencoded key)
  let manifestContent;
  try {
    const s3Obj = await s3.send(new GetObjectCommand({
      Bucket: OUTPUT_BUCKET,
      Key:    outputKey,  // raw key with spaces — S3 SDK handles encoding internally
    }));
    manifestContent = await s3Obj.Body.transformToString("utf-8");
  } catch (err) {
    console.error("Failed to fetch manifest from S3:", err);
    return respond(500, { error: "Could not fetch manifest" });
  }

  // Rewrite .ts segment lines with signed CloudFront URLs
  // URL-encode the full path before signing so the signature matches
  // what HLS.js sends — HLS.js always percent-encodes spaces in URLs
  const rewritten = manifestContent
    .split("\n")
    .map((line) => {
      const trimmed = line.trim();
      if (trimmed.endsWith(".ts") && !trimmed.startsWith("#")) {
        const fullKey    = folder + trimmed;
        // encode each path segment individually — don't encode the slash separators
        const encodedKey = fullKey.split("/").map((seg) => encodeURIComponent(seg)).join("/");
        console.log(`Signing segment: ${CF_DOMAIN}/${encodedKey}`);
        return signedUrl(encodedKey);
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

// POST /videos — creates a video metadata record in DynamoDB
async function createVideo(body) {
  let data;
  try {
    data = typeof body === "string" ? JSON.parse(body) : body;
  } catch {
    return respond(400, { error: "Invalid JSON body" });
  }

  const { video_id, title } = data;
  if (!video_id || !title) return respond(400, { error: "video_id and title are required" });

  const item = {
    ...data,
    status:     data.status || "pending",
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  try {
    await dynamo.send(new PutCommand({
      TableName:           TABLE_NAME,
      ConditionExpression: "attribute_not_exists(video_id)",
      Item:                item,
    }));
    return respond(201, { video: item });
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      await dynamo.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
      return respond(200, { video: item });
    }
    throw err;
  }
}

// PUT /videos/:id/status — updates transcoding status
async function updateVideoStatus(videoId, body) {
  let data;
  try {
    data = typeof body === "string" ? JSON.parse(body) : body;
  } catch {
    return respond(400, { error: "Invalid JSON body" });
  }

  if (!data.status) return respond(400, { error: "status is required" });

  const result = await dynamo.send(new UpdateCommand({
    TableName:                 TABLE_NAME,
    Key:                       { video_id: videoId },
    UpdateExpression:          "SET #st = :status, updated_at = :ts",
    ConditionExpression:       "attribute_exists(video_id)",
    ExpressionAttributeNames:  { "#st": "status" },
    ExpressionAttributeValues: { ":status": data.status, ":ts": new Date().toISOString() },
    ReturnValues:              "ALL_NEW",
  }));

  return respond(200, { video: result.Attributes });
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

exports.handler = async (event) => {
  const method         = event.requestContext?.http?.method || event.httpMethod || "GET";
  const path           = event.rawPath || event.path || "/";
  const normalizedPath = path.replace(/\/$/, "") || "/";

  console.log(`${method} ${normalizedPath}`);

  try {
    if (method === "GET" && normalizedPath === "/health") {
      return respond(200, { status: "ok" });
    }

    if (method === "GET" && normalizedPath === "/videos") {
      return await listVideos();
    }

    const manifestMatch = normalizedPath.match(/^\/videos\/([^/]+)\/manifest$/);
    if (method === "GET" && manifestMatch) {
      return await getManifest(decodeURIComponent(manifestMatch[1]));
    }

    const videoMatch = normalizedPath.match(/^\/videos\/([^/]+)$/);
    if (method === "GET" && videoMatch) {
      return await getVideo(decodeURIComponent(videoMatch[1]));
    }

    if (method === "POST" && normalizedPath === "/videos") {
      return await createVideo(event.body);
    }

    const statusMatch = normalizedPath.match(/^\/videos\/([^/]+)\/status$/);
    if (method === "PUT" && statusMatch) {
      return await updateVideoStatus(decodeURIComponent(statusMatch[1]), event.body);
    }

    return respond(404, { error: "Route not found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return respond(500, { error: "Internal server error" });
  }
};
