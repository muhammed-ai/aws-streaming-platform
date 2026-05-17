const { DynamoDBClient, PutItemCommand, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");
const { marshall } = require("@aws-sdk/util-dynamodb");

const dynamo = new DynamoDBClient({});
const TABLE  = process.env.DYNAMODB_TABLE;

/**
 * Triggered by EventBridge when a MediaConvert job changes state.
 * Writes or updates a DynamoDB record so the video appears in the catalog.
 *
 * EventBridge event shape (simplified):
 * {
 *   "detail-type": "MediaConvert Job State Change",
 *   "detail": {
 *     "status": "COMPLETE" | "ERROR" | "CANCELED",
 *     "jobId": "1234567890123-abcdef",
 *     "outputGroupDetails": [{ "outputDetails": [{ "outputFilePaths": ["s3://bucket/prefix/file_1080p.m3u8"] }] }],
 *     "userMetadata": { "video_id": "...", "title": "...", ... }  // set by trigger Lambda
 *   }
 * }
 */
exports.handler = async (event) => {
  console.log("EventBridge event:", JSON.stringify(event, null, 2));

  const detail = event.detail;
  const status = detail.status; // COMPLETE | ERROR | CANCELED

  // Extract the output S3 path from the first HLS output
  let outputKey = null;
  try {
    const filePath = detail.outputGroupDetails?.[0]?.outputDetails?.[0]?.outputFilePaths?.[0];
    if (filePath) {
      // filePath = "s3://netflix-dev-output/prefix/file_1080p.m3u8"
      // Strip the bucket portion to get just the key
      const url = new URL(filePath.replace("s3://", "https://"));
      // url.pathname = "/prefix/file_1080p.m3u8" — remove leading slash
      outputKey = url.pathname.replace(/^\/[^/]+\//, ""); // remove "/bucket-name/"
    }
  } catch (err) {
    console.warn("Could not parse output path:", err.message);
  }

  // Pull metadata from userMetadata if the trigger Lambda set it,
  // otherwise derive what we can from the job details
  const meta      = detail.userMetadata || {};
  const jobId     = detail.jobId || "";
  const inputFile = detail.inputFile || "";

  // Derive a video_id from the input filename if not provided
  // e.g. "s3://bucket/my-video.mp4" → "my-video"
  const videoId = meta.video_id || inputFile.split("/").pop().replace(/\.[^.]+$/, "") || jobId;

  // Title defaults to the filename without extension
  const title = meta.title || videoId.replace(/[-_]/g, " ").replace(/\b\w/g, c => c.toUpperCase());

  const dbStatus = status === "COMPLETE" ? "ready" : status === "ERROR" ? "error" : "processing";

  try {
    if (status === "COMPLETE" && outputKey) {
      // Upsert — create the record if it doesn't exist, update if it does
      await dynamo.send(new PutItemCommand({
        TableName: TABLE,
        Item: marshall({
          video_id:   videoId,
          title:      meta.title       || title,
          description: meta.description || "",
          genre:      meta.genre        || "Uncategorized",
          duration:   meta.duration     || 0,
          output_key: outputKey,
          status:     "ready",
          job_id:     jobId,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }),
        // If record already exists (created manually), update instead
        ConditionExpression: "attribute_not_exists(video_id)",
      }).catch(async (err) => {
        if (err.name === "ConditionalCheckFailedException") {
          // Record exists — just update status and output_key
          return dynamo.send(new UpdateItemCommand({
            TableName: TABLE,
            Key: marshall({ video_id: videoId }),
            UpdateExpression: "SET #st = :status, output_key = :key, updated_at = :ts",
            ExpressionAttributeNames: { "#st": "status" },
            ExpressionAttributeValues: marshall({
              ":status": "ready",
              ":key":    outputKey,
              ":ts":     new Date().toISOString(),
            }),
          }));
        }
        throw err;
      }));

      console.log(`Video ${videoId} marked as ready with key ${outputKey}`);
    } else {
      // Job failed or was cancelled — update status if record exists
      await dynamo.send(new UpdateItemCommand({
        TableName: TABLE,
        Key: marshall({ video_id: videoId }),
        UpdateExpression: "SET #st = :status, updated_at = :ts",
        ExpressionAttributeNames: { "#st": "status" },
        ExpressionAttributeValues: marshall({
          ":status": dbStatus,
          ":ts":     new Date().toISOString(),
        }),
      })).catch((err) => {
        // Record may not exist if job failed before we created it — that's fine
        if (err.name !== "ResourceNotFoundException") console.warn(err.message);
      });

      console.log(`Video ${videoId} status set to ${dbStatus}`);
    }
  } catch (err) {
    console.error("DynamoDB write failed:", err);
    throw err;
  }
};
