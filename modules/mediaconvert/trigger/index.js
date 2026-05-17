const {
  MediaConvertClient,
  CreateJobCommand,
} = require("@aws-sdk/client-mediaconvert");
const {
  DynamoDBClient,
  PutItemCommand,
} = require("@aws-sdk/client-dynamodb");
const { marshall } = require("@aws-sdk/util-dynamodb");

const mc     = new MediaConvertClient({ endpoint: process.env.MC_ENDPOINT });
const dynamo = new DynamoDBClient({});

exports.handler = async (event) => {
  // Decode S3 key — S3 encodes spaces and special chars e.g. "my video.mp4" → "my+video.mp4"
  const key    = decodeURIComponent(event.Records[0].s3.object.key.replace(/\+/g, " "));
  const bucket = event.Records[0].s3.bucket.name;

  // Derive a clean video ID from the filename without extension
  // e.g. "my-movie.mp4" → "my-movie"
  const filename     = key.split("/").pop();
  const videoId      = filename.replace(/\.[^.]+$/, "").trim();
  const outputPrefix = videoId;

  // Human-readable title from the filename
  // e.g. "my-movie-2024" → "My Movie 2024"
  const title = videoId
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());

  // Expected output key — matches the pattern MediaConvert uses with NameModifier "_1080p"
  const outputKey = `${outputPrefix}/${videoId}_1080p.m3u8`;

  console.log(`Processing upload: s3://${bucket}/${key}`);
  console.log(`video_id: ${videoId}, output_key: ${outputKey}`);

  // Write initial DynamoDB record so the video appears in the catalog immediately
  // with status "processing" — on_complete Lambda will update it to "ready"
  try {
    await dynamo.send(new PutItemCommand({
      TableName: process.env.DYNAMODB_TABLE,
      Item: marshall({
        video_id:    videoId,
        title:       title,
        description: "",
        genre:       "Uncategorized",
        duration:    0,
        output_key:  outputKey,
        status:      "processing",
        created_at:  new Date().toISOString(),
        updated_at:  new Date().toISOString(),
      }),
      // Overwrite if already exists — handles re-uploads of the same file
      // No condition so a re-upload resets the record cleanly
    }));
    console.log(`DynamoDB record created for ${videoId}`);
  } catch (err) {
    // Log but don't fail — MediaConvert job should still start even if DynamoDB write fails
    console.error(`DynamoDB write failed for ${videoId}:`, err.message);
  }

  // Start the MediaConvert transcoding job
  const command = new CreateJobCommand({
    Role: process.env.MC_ROLE_ARN,
    // Pass video metadata so on_complete Lambda can use it without re-deriving
    UserMetadata: {
      video_id:   videoId,
      title:      title,
      output_key: outputKey,
    },
    Settings: {
      Inputs: [{
        FileInput:      `s3://${bucket}/${key}`,
        AudioSelectors: { "Audio Selector 1": { DefaultSelection: "DEFAULT" } },
        VideoSelector:  {},
        TimecodeSource: "ZEROBASED",
      }],
      OutputGroups: [{
        Name: "HLS Group",
        OutputGroupSettings: {
          Type:             "HLS_GROUP_SETTINGS",
          HlsGroupSettings: {
            Destination:      `s3://${process.env.OUTPUT_BUCKET}/${outputPrefix}/`,
            SegmentLength:    6,
            MinSegmentLength: 0,
          },
        },
        Outputs: [{
          NameModifier:      "_1080p",
          ContainerSettings: { Container: "M3U8", M3u8Settings: {} },
          VideoDescription: {
            Width:  1920,
            Height: 1080,
            CodecSettings: {
              Codec: "H_264",
              H264Settings: {
                Bitrate:            5000000,
                RateControlMode:    "CBR",
                CodecProfile:       "HIGH",
                CodecLevel:         "AUTO",
                FramerateControl:   "INITIALIZE_FROM_SOURCE",
              },
            },
          },
          AudioDescriptions: [{
            CodecSettings: {
              Codec:       "AAC",
              AacSettings: { Bitrate: 96000, SampleRate: 48000, CodingMode: "CODING_MODE_2_0" },
            },
          }],
        }],
      }],
    },
  });

  const response = await mc.send(command);
  console.log(`MediaConvert job created: ${response.Job.Id}`);
};
