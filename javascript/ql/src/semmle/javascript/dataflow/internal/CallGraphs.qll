/**
 * Internal predicates for computing the call graph.
 */

private import javascript
private import semmle.javascript.dataflow.internal.StepSummary
private import semmle.javascript.dataflow.internal.PreCallGraphStep

cached
module CallGraph {
  /** Gets the function referenced by `node`, as determined by the type inference. */
  cached
  Function getAFunctionValue(AnalyzedNode node) {
    result = node.getAValue().(AbstractCallable).getFunction()
  }

  /** Holds if the type inferred for `node` is indefinite due to global flow. */
  cached
  predicate isIndefiniteGlobal(AnalyzedNode node) {
    node.analyze().getAValue().isIndefinite("global")
  }

  /**
   * Gets a data flow node that refers to the given function.
   *
   * Note that functions are not currently type-tracked, but this exposes the type-tracker `t`
   * from underlying class tracking if the function came from a class or instance.
   */
  pragma[nomagic]
  private DataFlow::SourceNode getAFunctionReference(
    DataFlow::FunctionNode function, int imprecision, DataFlow::TypeTracker t
  ) {
    t.start() and
    exists(Function fun |
      fun = function.getFunction() and
      fun = getAFunctionValue(result)
    |
      if isIndefiniteGlobal(result)
      then
        fun.getFile() = result.getFile() and imprecision = 0
        or
        fun.inExternsFile() and imprecision = 1
        or
        imprecision = 2
      else imprecision = 0
    )
    or
    imprecision = 0 and
    t.start() and
    AccessPath::step(function, result)
    or
    t.start() and
    imprecision = 0 and
    PreCallGraphStep::step(any(DataFlow::Node n | function.flowsTo(n)), result)
    or
    imprecision = 0 and
    result = callgraphStep(function, t)
  }

  /**
   * Gets a reference to `function` type-tracked by `t`.
   *
   * This only includes steps that aren't included in ordinary type-tracking.
   * For example, this steps from a method definition to an access on an instance, but
   * does not step through access paths, as those are included in type-tracking already.
   */
  cached
  DataFlow::SourceNode callgraphStep(DataFlow::FunctionNode function, DataFlow::TypeTracker t) {
    exists(DataFlow::ClassNode cls |
      exists(string name |
        function = cls.getInstanceMethod(name) and
        cls.getAnInstanceMemberAccess(name, t.continue()) = result
        or
        function = cls.getStaticMethod(name) and
        cls.getAClassReference(t.continue()).getAPropertyRead(name) = result
      )
      or
      function = cls.getConstructor() and
      cls.getAClassReference(t.continue()) = result
    )
    or
    exists(DataFlow::FunctionNode outer |
      result = getAFunctionReference(outer, 0, t.continue()).getAnInvocation() and
      locallyReturnedFunction(outer, function)
    )
  }

  private predicate locallyReturnedFunction(
    DataFlow::FunctionNode outer, DataFlow::FunctionNode inner
  ) {
    inner.flowsTo(outer.getAReturn())
  }

  /**
   * Gets a data flow node that refers to the given function.
   */
  cached
  DataFlow::SourceNode getAFunctionReference(DataFlow::FunctionNode function, int imprecision) {
    result = getAFunctionReference(function, imprecision, DataFlow::TypeTracker::end())
  }

  /**
   * Gets a data flow node that refers to the result of the given partial function invocation,
   * with `function` as the underlying function.
   */
  pragma[nomagic]
  private DataFlow::SourceNode getABoundFunctionReferenceAux(
    DataFlow::FunctionNode function, int boundArgs, DataFlow::TypeTracker t
  ) {
    exists(DataFlow::PartialInvokeNode partial, DataFlow::Node callback |
      result = partial.getBoundFunction(callback, boundArgs) and
      getAFunctionReference(function, 0, t.continue()).flowsTo(callback)
    )
    or
    exists(StepSummary summary, DataFlow::TypeTracker t2 |
      result = getABoundFunctionReferenceAux(function, boundArgs, t2, summary) and
      t = t2.append(summary)
    )
  }

  pragma[noinline]
  private DataFlow::SourceNode getABoundFunctionReferenceAux(
    DataFlow::FunctionNode function, int boundArgs, DataFlow::TypeTracker t, StepSummary summary
  ) {
    exists(DataFlow::SourceNode prev |
      prev = getABoundFunctionReferenceAux(function, boundArgs, t) and
      StepSummary::step(prev, result, summary)
    )
  }

  /**
   * Gets a data flow node that refers to the result of the given partial function invocation,
   * with `function` as the underlying function.
   */
  cached
  DataFlow::SourceNode getABoundFunctionReference(
    DataFlow::FunctionNode function, int boundArgs, boolean contextDependent
  ) {
    exists(DataFlow::TypeTracker t |
      result = getABoundFunctionReferenceAux(function, boundArgs, t) and
      t.end() and
      contextDependent = t.hasCall()
    )
  }

  /**
   * Gets a possible callee of `node` with the given `imprecision`.
   *
   * Does not include custom call edges.
   */
  cached
  DataFlow::FunctionNode getACallee(DataFlow::InvokeNode node, int imprecision) {
    getAFunctionReference(result, imprecision).flowsTo(node.getCalleeNode())
    or
    imprecision = 0 and
    exists(InvokeExpr expr | expr = node.(DataFlow::Impl::ExplicitInvokeNode).asExpr() |
      result.getFunction() = expr.getResolvedCallee()
      or
      exists(DataFlow::ClassNode cls |
        expr.(SuperCall).getBinder() = cls.getConstructor().getFunction() and
        result = cls.getADirectSuperClass().getConstructor()
      )
    )
  }
}
