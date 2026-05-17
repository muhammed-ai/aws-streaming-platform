const { DynamoDBClient, DeleteItemCommand } = require("@aws-sdk/client-dynamodb");
const { S3Client, ListObjectsV2Command, DeleteObjectsCommand } = require("@aws-sdk/client-s3");
const { marshall } = require("@aws-sdk/util-dynamodb");

const dynamo = new DynamoDBClient({});
const s3     = new S3Client({});

const TABLE         = process.env.DYNAMODB_TABLE;
const OUTPUT_BUCKET = process.env.OUTPUT_BUCKET;

exports.handler = async (event) => {
  for (const record of event.Records) {
    const key      = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    const filename = key.split("/").pop();
    const videoId  = filename.replace(/\.[^.]+$/, "").trim();

    console.log(`Input deleted: ${key}, video_id: ${videoId}`);

    // 1. Delete all HLS output files from the output bucket
    try {
      const listed = await s3.send(new ListObjectsV2Command({
        Bucket: OUTPUT_BUCKET,
        Prefix: `${videoId}/`,
      }));

      if (listed.Contents && listed.Contents.length > 0) {
        await s3.send(new DeleteObjectsCommand({
          Bucket: OUTPUT_BUCKET,
          Delete: {
            Objects: listed.Contents.map((obj) => ({ Key: obj.Key })),
            Quiet:   true,
          },
        }));
        console.log(`Deleted ${listed.Contents.length} output files for ${videoId}`);
      }
    } catch (err) {
      console.error(`Failed to delete output files for ${videoId}:`, err.message);
    }

    // 2. Delete the DynamoDB record
    try {
      await dynamo.send(new DeleteItemCommand({
        TableName: TABLE,
        Key:       marshall({ video_id: videoId }),
      }));
      console.log(`Deleted DynamoDB record for ${videoId}`);
    } catch (err) {
      console.error(`Failed to delete DynamoDB record for ${videoId}:`, err.message);
    }
  }
};
