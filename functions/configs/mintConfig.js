const fs = require("fs");

const {
  Location,
  ReturnType,
  CodeLanguage,
} = require("@chainlink/functions-toolkit");

const requestConfig = {
  source: fs.readFileSync("./sources/stockPriceSource.js").toString(),
  codeLocation: Location.InLine,
  args: [],
  codeLanguage: CodeLanguage.JavaScript,
  expectedReturnType: ReturnType.uint256,
};

module.exports = requestConfig;
