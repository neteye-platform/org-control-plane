// Runs a github-script script with a fake client and prints its API calls as JSON.
// Usage: node github_script_harness.js <script file> <existing comments JSON>

'use strict';

const fs = require('fs');

const [scriptFile, existingComments] = process.argv.slice(2);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const calls = [];

const github = {
  paginate: async (method, params) => {
    calls.push({ call: 'listComments', issue_number: params.issue_number });
    return JSON.parse(existingComments);
  },
  rest: {
    issues: {
      listComments: () => {},
      createComment: async ({ issue_number, body }) => calls.push({ call: 'createComment', issue_number, body }),
      updateComment: async ({ comment_id, body }) => calls.push({ call: 'updateComment', comment_id, body }),
      deleteComment: async ({ comment_id }) => calls.push({ call: 'deleteComment', comment_id }),
    },
  },
};
const context = {
  repo: { owner: 'acme', repo: 'control-plane' },
  issue: { number: 7 },
  serverUrl: 'https://github.com',
  runId: 42,
};
const core = { info: () => {} };

new AsyncFunction('require', 'github', 'context', 'core', fs.readFileSync(scriptFile, 'utf8'))(
  require,
  github,
  context,
  core,
)
  .then(() => process.stdout.write(JSON.stringify(calls)))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
