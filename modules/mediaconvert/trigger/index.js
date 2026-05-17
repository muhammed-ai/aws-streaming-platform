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
  const filename     = key.split("/").pop();
  const videoId      = filename.replace(/\.[^.]+$/, "").trim();
  const outputPrefix = videoId;

  // Human-readable title from the filename
  const title = videoId
    .replace(/[-_]/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());

  // Expected output key — matches the pattern MediaConvert uses with NameModifier "_1080p"
  const outputKey     = `${outputPrefix}/${videoId}_1080p.m3u8`;
  // Thumbnail key — MediaConvert appends .0000000.jpg to FRAME_CAPTURE output
  const thumbnailKey  = `${outputPrefix}/${videoId}_thumbnail.0000000.jpg`;

  console.log(`Processing upload: s3://${bucket}/${key}`);
  console.log(`video_id: ${videoId}, output_key: ${outputKey}`);

  // Write initial DynamoDB record with processing status
  try {
    await dynamo.send(new PutItemCommand({
      TableName: process.env.DYNAMODB_TABLE,
      Item: marshall({
        video_id:      videoId,
        title:         title,
        description:   "",
        genre:         "Uncategorized",
        duration:      0,
        output_key:    outputKey,
        thumbnail_key: thumbnailKey,
        status:        "processing",
        created_at:    new Date().toISOString(),
        updated_at:    new Date().toISOString(),
      }),
    }));
    console.log(`DynamoDB record created for ${videoId}`);
  } catch (err) {
    console.error(`DynamoDB write failed for ${videoId}:`, err.message);
  }

  const command = new CreateJobCommand({
    Role: process.env.MC_ROLE_ARN,
    UserMetadata: {
      video_id:      videoId,
      title:         title,
      output_key:    outputKey,
      thumbnail_key: thumbnailKey,
    },
    Settings: {
      Inputs: [{
        FileInput:      `s3://${bucket}/${key}`,
        AudioSelectors: { "Audio Selector 1": { DefaultSelection: "DEFAULT" } },
        VideoSelector:  {},
        TimecodeSource: "ZEROBASED",
      }],
      OutputGroups: [
        // HLS transcoding group
        {
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
                  Bitrate:           5000000,
                  RateControlMode:   "CBR",
                  CodecProfile:      "HIGH",
                  CodecLevel:        "AUTO",
                  FramerateControl:  "INITIALIZE_FROM_SOURCE",
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
        },
        // Thumbnail group — captures a single JPEG frame at the start of the video
        {
          Name: "Thumbnail",
          OutputGroupSettings: {
            Type:              "FILE_GROUP_SETTINGS",
            FileGroupSettings: {
              Destination: `s3://${process.env.OUTPUT_BUCKET}/${outputPrefix}/`,
            },
          },
          Outputs: [{
            NameModifier:      "_thumbnail",
            ContainerSettings: { Container: "RAW" },
            VideoDescription: {
              Width:  640,
              Height: 360,
              CodecSettings: {
                Codec: "FRAME_CAPTURE",
                FrameCaptureSettings: {
                  FramerateNumerator:   1,
                  FramerateDenominator: 1,
                  MaxCaptures:          1,
                  Quality:              80,
                },
              },
            },
          }],
        },
      ],
    },
  });

  const response = await mc.send(command);
  console.log(`MediaConvert job created: ${response.Job.Id}`);
};
