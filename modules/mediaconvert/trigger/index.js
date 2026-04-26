const {
  MediaConvertClient,
  CreateJobCommand,
} = require("@aws-sdk/client-mediaconvert");

// SDK v3 — client initialised with the account-specific regional endpoint
const mc = new MediaConvertClient({ endpoint: process.env.MC_ENDPOINT });

exports.handler = async (event) => {
  // Decode S3 key — S3 encodes spaces and special chars e.g. "my video.mp4" → "my+video.mp4"
  const key = decodeURIComponent(
    event.Records[0].s3.object.key.replace(/\+/g, " ")
  );
  const bucket = event.Records[0].s3.bucket.name;
  const outputPrefix = key.split(".")[0];

  console.log(`Starting MediaConvert job for s3://${bucket}/${key}`);

  const command = new CreateJobCommand({
    Role: process.env.MC_ROLE_ARN,
    Settings: {
      Inputs: [{
        FileInput: `s3://${bucket}/${key}`,
        AudioSelectors: { "Audio Selector 1": { DefaultSelection: "DEFAULT" } },
        VideoSelector: {},
        TimecodeSource: "ZEROBASED"
      }],
      OutputGroups: [
        {
          Name: "HLS Group",
          OutputGroupSettings: {
            Type: "HLS_GROUP_SETTINGS",
            HlsGroupSettings: {
              Destination: `s3://${process.env.OUTPUT_BUCKET}/${outputPrefix}/`,
              SegmentLength: 6,
              MinSegmentLength: 0,
            },
          },
          Outputs: [
            {
              NameModifier: "_1080p",
              ContainerSettings: { Container: "M3U8", M3u8Settings: {} },
              VideoDescription: {
                Width: 1920,
                Height: 1080,
                CodecSettings: {
                  Codec: "H_264",
                  H264Settings: {
                    Bitrate: 5000000,
                    RateControlMode: "CBR",
                    CodecProfile: "HIGH",
                    CodecLevel: "AUTO",
                    FramerateControl: "INITIALIZE_FROM_SOURCE",
                  },
                },
              },
              AudioDescriptions: [{
                CodecSettings: {
                  Codec: "AAC",
                  AacSettings: { Bitrate: 96000, SampleRate: 48000, CodingMode: "CODING_MODE_2_0" },
                },
              }],
            },
          ],
        },
      ],
    },
  });

  const response = await mc.send(command);
  console.log(`MediaConvert job created: ${response.Job.Id}`);
};
