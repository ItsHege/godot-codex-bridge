import { startStdioServer } from "./server.js";

startStdioServer().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
