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
      Inputs: [{ FileInput: `s3://${bucket}/${key}` }],
      OutputGroups: [
        {
          OutputGroupSettings: {
            Type: "HLS_GROUP_SETTINGS",
            HlsGroupSettings: {
              Destination: `s3://${process.env.OUTPUT_BUCKET}/${outputPrefix}/`,
            },
          },
          Outputs: [
            { Preset: "System-Avc_16x9_1080p_29_97fps_8500kbps_qvbr" },
          ],
        },
      ],
    },
  });

  const response = await mc.send(command);
  console.log(`MediaConvert job created: ${response.Job.Id}`);
};
