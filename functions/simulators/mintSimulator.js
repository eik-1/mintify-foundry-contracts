const {
  simulateScript,
  decodeResult,
} = require("@chainlink/functions-toolkit");
const requestConfig = require("./mintConfig");

async function main() {
  const { responseBytesHexstring, errorString } = await simulateScript(
    requestConfig
  );
  if (responseBytesHexstring) {
    console.log(
      `Response is: ${decodeResult(
        responseBytesHexstring,
        requestConfig.expectedReturnType
      ).toString()}\n`
    );
  }
  if (errorString) {
    console.error(`Error: ${errorString}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
