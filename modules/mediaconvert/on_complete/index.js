const {
  DynamoDBClient,
  PutItemCommand,
  UpdateItemCommand,
} = require("@aws-sdk/client-dynamodb");
const { marshall } = require("@aws-sdk/util-dynamodb");

const dynamo = new DynamoDBClient({});
const TABLE  = process.env.DYNAMODB_TABLE;

exports.handler = async (event) => {
  console.log("EventBridge event:", JSON.stringify(event, null, 2));

  const detail = event.detail;
  const status = detail.status;

  // Only act on terminal states
  if (!["COMPLETE", "ERROR", "CANCELED"].includes(status)) {
    console.log(`Ignoring non-terminal status: ${status}`);
    return;
  }

  // Extract output file path from the event
  // e.g. "s3://netflix-dev-output/test-media-converter/test-media-converter_1080p.m3u8"
  let outputKey  = null;
  let videoId    = null;

  try {
    const filePath = detail.outputGroupDetails?.[0]?.outputDetails?.[0]?.outputFilePaths?.[0];
    if (filePath) {
      // Strip "s3://bucket-name/" to get just the key
      // filePath = "s3://netflix-dev-output/folder/file.m3u8"
      const withoutProtocol = filePath.replace("s3://", "");
      const slashIndex      = withoutProtocol.indexOf("/");
      outputKey             = withoutProtocol.substring(slashIndex + 1);

      // video_id is the folder name — e.g. "test-media-converter"
      videoId = outputKey.split("/")[0];
    }
  } catch (err) {
    console.warn("Could not parse output path:", err.message);
  }

  // Fall back to job ID if we couldn't derive video_id from the path
  if (!videoId) {
    videoId = detail.jobId || "unknown";
  }

  // Use userMetadata if the trigger Lambda set it (newer uploads)
  const meta  = detail.userMetadata || {};
  const title = meta.title || videoId.replace(/[-_]/g, " ").replace(/\b\w/g, c => c.toUpperCase());

  const dbStatus = status === "COMPLETE" ? "ready" : status === "ERROR" ? "error" : "processing";
  const now      = new Date().toISOString();

  console.log(`video_id=${videoId}, status=${dbStatus}, output_key=${outputKey}`);

  if (status === "COMPLETE" && outputKey) {
    // Try to create the record — if it already exists, update it instead
    try {
      await dynamo.send(new PutItemCommand({
        TableName:           TABLE,
        ConditionExpression: "attribute_not_exists(video_id)",
        Item: marshall({
          video_id:    videoId,
          title:       meta.title       || title,
          description: meta.description || "",
          genre:       meta.genre        || "Uncategorized",
          duration:    meta.duration     || 0,
          output_key:  outputKey,
          status:      "ready",
          job_id:      detail.jobId || "",
          created_at:  now,
          updated_at:  now,
        }),
      }));
      console.log(`Created DynamoDB record for ${videoId}`);
    } catch (err) {
      if (err.name === "ConditionalCheckFailedException") {
        // Record already exists — just update status and output_key
        await dynamo.send(new UpdateItemCommand({
          TableName:                 TABLE,
          Key:                       marshall({ video_id: videoId }),
          UpdateExpression:          "SET #st = :status, output_key = :key, updated_at = :ts",
          ExpressionAttributeNames:  { "#st": "status" },
          ExpressionAttributeValues: marshall({
            ":status": "ready",
            ":key":    outputKey,
            ":ts":     now,
          }),
        }));
        console.log(`Updated DynamoDB record for ${videoId}`);
      } else {
        throw err;
      }
    }
  } else {
    // Job failed — update status if record exists, ignore if it doesn't
    try {
      await dynamo.send(new UpdateItemCommand({
        TableName:                 TABLE,
        Key:                       marshall({ video_id: videoId }),
        ConditionExpression:       "attribute_exists(video_id)",
        UpdateExpression:          "SET #st = :status, updated_at = :ts",
        ExpressionAttributeNames:  { "#st": "status" },
        ExpressionAttributeValues: marshall({
          ":status": dbStatus,
          ":ts":     now,
        }),
      }));
      console.log(`Updated status to ${dbStatus} for ${videoId}`);
    } catch (err) {
      if (err.name !== "ConditionalCheckFailedException") {
        throw err;
      }
    }
  }
};
