// Minimal ESLint flat config for the drupal-agentic-workflow repo itself.
//
// This repository is a Bash/Node tooling template, not a JS application, and
// its zero-dependency `.mjs` tools carry no lint ruleset. This empty config
// exists only so the dogfooded post-generation-lint hook (which runs `eslint`
// on edited `.mjs`/`.js` files) finds a config and passes instead of erroring
// with "couldn't find an eslint.config file". Formatting is enforced by
// Prettier; correctness of the tools is covered by tests/.
export default [];
