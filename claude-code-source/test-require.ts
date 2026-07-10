import "tsx/cjs";
import { createRequire } from "module";
const req = createRequire(import.meta.url);
console.log("starting...");
try {
  const mod = req("./src/tools/SendMessageTool/SendMessageTool.ts");
  console.log("loaded!", Object.keys(mod));
} catch (e) {
  console.error("error!", e);
}
