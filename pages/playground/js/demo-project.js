// The sample project seeded into the virtual file system.
export const DEMO_PROJECT = {
  "README.md":
    "# Demo Project\n\n" +
    "A tiny sample project for the CCHarbour playground. Ask the assistant " +
    "to read, search, or edit these files.\n",
  "package.json":
    "{\n  \"name\": \"demo\",\n  \"version\": \"1.0.0\",\n" +
    "  \"type\": \"module\"\n}\n",
  "src/main.js":
    "import { greet } from './greet.js';\n\n" +
    "console.log(greet('world'));\n",
  "src/greet.js":
    "export function greet(name) {\n" +
    "  return 'Hello, ' + name + '!';\n" +
    "}\n",
};
