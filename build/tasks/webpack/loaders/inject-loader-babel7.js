"use strict";
// Experimental test-only loader; not wired into the test build.
const babel = require("@babel/core");
module.exports = function(source, inputMap) {
  const plugin = ({types:t}) => ({visitor:{
    CallExpression(path) {
      const n=path.node;
      if (!t.isIdentifier(n.callee,{name:"require"}) || n.arguments.length!==1 ||
          !t.isStringLiteral(n.arguments[0]) || path.scope.hasBinding("require")) return;
      const request=n.arguments[0].value;
      const mocks=t.identifier("__streamhubInjections");
      const own=t.callExpression(t.memberExpression(
        t.memberExpression(t.memberExpression(t.identifier("Object"),t.identifier("prototype")),t.identifier("hasOwnProperty")),
        t.identifier("call")), [mocks,t.stringLiteral(request)]);
      path.replaceWith(t.conditionalExpression(own,
        t.memberExpression(mocks,t.stringLiteral(request),true),
        t.callExpression(t.identifier("require"),[t.stringLiteral(request)])));
      path.skip();
    }
  }});
  const result=babel.transformSync(source,{babelrc:false,configFile:false,sourceType:"script",plugins:[plugin],filename:this.resourcePath});
  this.callback(null,["module.exports = function(__streamhubInjections) {",
    "__streamhubInjections = __streamhubInjections || {};",
    "var module = {exports:{}}; var exports = module.exports;",
    result.code,"return module.exports;","};"].join("\n"),inputMap);
};
