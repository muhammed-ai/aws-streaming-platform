const AWS = require("aws-sdk");

exports.handler = async () => {
  const signer = new AWS.CloudFront.Signer(
    process.env.KEY_PAIR_ID,
    process.env.PRIVATE_KEY
  );

  const url = signer.getSignedUrl({
    url: process.env.CF_URL + "/video.m3u8",
    expires: Math.floor(Date.now() / 1000) + 3600,
  });

  return {
    statusCode: 200,
    body: JSON.stringify({ url }),
  };
};