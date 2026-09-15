"""A bounded interpreter for fixture expressions, never production or arbitrary Python.

Unsupported syntax and missing fixture dependencies are data, not guessed values.
Only the selected pure standard-library constructors/methods below can execute.
"""
import ast
import datetime
import functools
import inspect
import operator
import types
import zoneinfo


# Compound statements whose body runs in sequence with the code around it, so a
# guard inside is an ordinary guard rather than opaque control flow.
INLINE_BODY = (ast.If, ast.With, ast.AsyncWith, ast.Try)


class Gap(Exception):
    pass


class OpaqueCall(Gap):
    """A call that was not run, so it may have changed any mutable object."""


class Unknown:
    def __init__(self, reason):
        self.reason = reason


MODULES = {'datetime': datetime, 'zoneinfo': zoneinfo, 'functools': functools,
           'types': types}
EXPORTS = {'datetime': {'datetime', 'date', 'time', 'timedelta', 'timezone', 'UTC'},
           'zoneinfo': {'ZoneInfo'}, 'functools': {'lru_cache'},
           'types': {'SimpleNamespace'}}
BUILTINS = {k: v for k, v in vars(__import__('builtins')).items()
            if k in {'len', 'str', 'int', 'float', 'bool', 'tuple', 'list', 'dict',
                     'set', 'abs', 'min', 'max', 'all', 'any', 'sorted'}}
# Diagnostics are evaluated for dependencies but never emitted into the JSON stream.
def fixture_print(*args, sep=' ', end='\n', file=None, flush=False):
    if file is not None:
        raise Gap('printing to a fixture stream is unsupported')


BUILTINS['print'] = fixture_print
MAX_SEQUENCE_SIZE = 100000
SAFE_CALLS = list(BUILTINS.values()) + [datetime.datetime, datetime.date, datetime.time,
    datetime.timedelta, datetime.timezone, zoneinfo.ZoneInfo, types.SimpleNamespace]
METHODS = {'astimezone', 'utcoffset', 'dst', 'date', 'time', 'replace', 'combine',
           'isoformat', 'total_seconds', 'cache_info', 'cache_parameters'}
BINOPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
          ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod}
CMPS = {ast.Eq: operator.eq, ast.NotEq: operator.ne, ast.Is: operator.is_,
        ast.IsNot: operator.is_not, ast.Lt: operator.lt, ast.LtE: operator.le,
        ast.Gt: operator.gt, ast.GtE: operator.ge, ast.In: lambda a,b:a in b,
        ast.NotIn: lambda a,b:a not in b}
# Values a call that never ran cannot have changed. Tuples are left out rather
# than walked: they may hold mutable items, and walking them has no step budget.
IMMUTABLE = (int, float, complex, str, bytes, type(None), Unknown, types.ModuleType,
             datetime.date, datetime.time, datetime.timedelta, datetime.tzinfo)


class Evaluator:
    def __init__(self, production):
        self.production = set(production)
        self.env = dict(BUILTINS)
        self.checks = []
        self.functions = {}
        self.allowed_helpers = []
        self.steps = 0

    def expression(self, node, env):
        self.steps += 1
        if self.steps > 10000:
            raise Gap('evaluation step limit')
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Name):
            value = env.get(node.id, Unknown('unavailable name: ' + node.id))
            if isinstance(value, Unknown):
                raise Gap(value.reason)
            return value
        if isinstance(node, ast.Attribute):
            if node.attr.startswith('_'):
                raise Gap('private attribute access is unsupported')
            value = self.expression(node.value, env)
            if isinstance(value, types.ModuleType):
                if node.attr not in EXPORTS.get(value.__name__, set()):
                    raise Gap('unsupported module attribute: ' + node.attr)
            return getattr(value, node.attr)
        if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            values = [self.expression(n, env) for n in node.elts]
            return {ast.List: list, ast.Tuple: tuple, ast.Set: set}[type(node)](values)
        if isinstance(node, ast.Dict):
            return {self.expression(k, env): self.expression(v, env)
                    for k, v in zip(node.keys, node.values)}
        if isinstance(node, ast.Subscript):
            return self.expression(node.value, env)[self.expression(node.slice, env)]
        if isinstance(node, ast.UnaryOp):
            fn = {ast.Not: operator.not_, ast.USub: operator.neg, ast.UAdd: operator.pos}.get(type(node.op))
            if fn:
                return fn(self.expression(node.operand, env))
        if isinstance(node, ast.BinOp) and type(node.op) in BINOPS:
            a, b = self.expression(node.left, env), self.expression(node.right, env)
            if isinstance(node.op, ast.Mod) and isinstance(a, (str, bytes)):
                raise Gap('string formatting is unsupported: unbounded allocation')
            if isinstance(node.op, ast.Mult):
                for sequence, factor in ((a, b), (b, a)):
                    if isinstance(sequence, (str, bytes, list, tuple)) and isinstance(factor, int):
                        if len(sequence) * max(0, factor) > MAX_SEQUENCE_SIZE:
                            raise Gap('sequence repetition size limit')
                if any(isinstance(x, int) and abs(x) > 10000 for x in (a, b)):
                    raise Gap('multiplication size limit')
            if isinstance(node.op, ast.Add) and isinstance(a, (str, bytes, list, tuple)) and type(a) is type(b):
                if len(a) + len(b) > MAX_SEQUENCE_SIZE:
                    raise Gap('sequence concatenation size limit')
            return BINOPS[type(node.op)](a, b)
        if isinstance(node, ast.Compare):
            a = self.expression(node.left, env)
            for op, right in zip(node.ops, node.comparators):
                b = self.expression(right, env)
                if not CMPS[type(op)](a,b):
                    return False
                a = b
            return True
        if isinstance(node, ast.BoolOp):
            value = None
            for item in node.values:
                value = self.expression(item, env)
                if isinstance(node.op, ast.And) and not value or isinstance(node.op, ast.Or) and value:
                    break
            return value
        if isinstance(node, ast.IfExp):
            return self.expression(node.body if self.expression(node.test, env) else node.orelse, env)
        if isinstance(node, ast.Call):
            try:
                fn = self.expression(node.func, env)
                args = [self.expression(a, env) for a in node.args]
                kwargs = {k.arg: self.expression(k.value, env) for k in node.keywords}
                if None in kwargs:
                    raise Gap('keyword expansion unsupported')
            except Exception as exc:
                raise OpaqueCall(str(exc))
            allowed = any(fn is f for f in SAFE_CALLS + self.allowed_helpers)
            if isinstance(node.func, ast.Attribute) and node.func.attr in METHODS:
                owner = getattr(fn, '__self__', getattr(fn, '__objclass__', None))
                allowed |= (isinstance(owner, (datetime.datetime, datetime.date, datetime.time,
                    datetime.timedelta, datetime.tzinfo, functools._lru_cache_wrapper))
                    or owner is datetime.datetime)
                if node.func.attr == 'astimezone':
                    zone = args[0] if args else kwargs.get('tz')
                    if zone is None or not isinstance(owner, datetime.datetime) or owner.utcoffset() is None:
                        raise Gap('host timezone is not established; use an aware datetime and explicit zone')
            if not allowed:
                raise OpaqueCall('unsupported call: ' + ast.unparse(node.func))
            try:
                return fn(*args, **kwargs)
            except Gap as exc:
                # A supported helper may stop at an unsupported statement.
                raise OpaqueCall(str(exc))
        raise Gap('unsupported expression: ' + type(node).__name__)

    def calls_production(self, node, seen=None):
        seen = set() if seen is None else seen
        for call in (n for n in ast.walk(node) if isinstance(n, ast.Call)):
            name = ast.unparse(call.func)
            if name in self.production or name.rsplit('.', 1)[-1] in self.production:
                return True
            if name in self.functions and name not in seen:
                if self.calls_production(self.functions[name], seen | {name}):
                    return True
        return False

    def assertion(self, node, env, scope, reason=None):
        check = {'id': f'python:{scope}:{node.lineno}', 'scope': scope,
                 'line': node.lineno, 'expression': ast.unparse(node.test), 'kind': 'fixture-assertion'}
        try:
            if reason:
                raise Gap(reason)
            held = bool(self.expression(node.test, env))
            check.update(status='held' if held else 'did-not-hold', detail=f'evaluated to {held}')
        except Exception as exc:
            check.update(status='could-not-evaluate', detail=f'{type(exc).__name__}: {exc}')
            if isinstance(exc, OpaqueCall):
                self.forget_mutable(env, 'unevaluated call: ' + str(exc))
        self.checks.append(check)

    def assign(self, target, value, env):
        if isinstance(target, ast.Name):
            env[target.id] = value
        elif isinstance(target, (ast.Tuple, ast.List)):
            if isinstance(value, Unknown):
                for t in target.elts:
                    self.assign(t, value, env)
            else:
                if len(target.elts) != len(value):
                    raise Gap('unpacking width mismatch')
                for t, v in zip(target.elts, value):
                    self.assign(t, v, env)
        else:
            raise Gap('assignment target unsupported')

    def forget_mutable(self, env, reason):
        # A call that never ran may have changed any mutable object, and every
        # mutable binding might alias one it reached. Helpers read self.env,
        # including when the call occurred in a copied test-function scope.
        scopes = [env] if env is self.env else [env, self.env]
        for bindings in scopes:
            for name, value in list(bindings.items()):
                immutable_callable = (any(value is f for f in SAFE_CALLS)
                                      or isinstance(value, types.FunctionType))
                if not isinstance(value, IMMUTABLE) and not immutable_callable:
                    bindings[name] = Unknown(reason)

    def invalidate(self, env, reason):
        # Unknown writes may affect aliases as well as their syntactic target.
        for name, value in list(env.items()):
            if name not in BUILTINS and not isinstance(value, types.ModuleType) and not any(value is f for f in SAFE_CALLS):
                env[name] = Unknown(reason)

    def unexecuted_guards(self, node, env, scope, reason):
        for inner in ast.walk(node):
            if isinstance(inner, ast.Assert):
                self.assertion(inner, env, scope, reason)

    def statements(self, nodes, env, scope):
        for node in nodes:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            if not isinstance(node, INLINE_BODY) and self.calls_production(node):
                # Never abandon a statement without recording the guards inside
                # it. Returning here silently made an answer whose false guard
                # shares a loop with a production call indistinguishable from
                # one carrying no guards at all.
                self.unexecuted_guards(node, env, scope,
                                       'guard shares a statement with a production call')
                return True
            if isinstance(node, ast.Assert):
                self.assertion(node, env, scope)
            elif isinstance(node, (ast.Assign, ast.AnnAssign)):
                try:
                    value = self.expression(node.value, env)
                except Exception as exc:
                    value = Unknown(str(exc))
                    if isinstance(exc, OpaqueCall):
                        self.forget_mutable(env, 'unevaluated call: ' + str(exc))
                for target in node.targets if isinstance(node, ast.Assign) else [node.target]:
                    try:
                        self.assign(target, value, env)
                    except Exception as exc:
                        self.invalidate(env, str(exc))
            elif isinstance(node, ast.If):
                if self.calls_production(node.test):
                    return True
                try:
                    branch = node.body if self.expression(node.test, env) else node.orelse
                except Exception as exc:
                    self.unexecuted_guards(node, env, scope, 'branch cannot be selected: ' + str(exc))
                    self.invalidate(env, 'unresolved branch effects')
                    if self.calls_production(node):
                        return True
                else:
                    if self.statements(branch, env, scope):
                        return True
            elif isinstance(node, (ast.With, ast.AsyncWith)):
                for item in node.items:
                    if self.calls_production(item.context_expr):
                        return True
                    # Neither __enter__ nor __exit__ is executed. Keep constants
                    # built inside the body checkable, but not pre-effect objects.
                    self.forget_mutable(env, 'context entry effects are not evaluated')
                    if item.optional_vars is not None:
                        try:
                            self.assign(item.optional_vars, Unknown('context value is not evaluated'), env)
                        except Exception as exc:
                            self.invalidate(env, str(exc))
                if self.statements(node.body, env, scope):
                    return True
                self.forget_mutable(env, 'context exit effects are not evaluated')
            elif isinstance(node, ast.Try):
                if self.statements(node.body, env, scope):
                    return True
                tails = [*node.handlers, *node.orelse, *node.finalbody]
                for tail in tails:
                    self.unexecuted_guards(tail, env, scope, 'exception and try-tail flow is not evaluated')
                if tails:
                    self.invalidate(env, 'exception and try-tail effects are not evaluated')
                if any(self.calls_production(tail) for tail in tails):
                    return True
            elif isinstance(node, (ast.Import, ast.ImportFrom)):
                self.imports(node, env)
            elif isinstance(node, ast.Expr) and not isinstance(node.value, ast.Constant):
                try:
                    self.expression(node.value, env)
                except Exception as exc:
                    self.invalidate(env, 'unsupported setup expression: ' + str(exc))
            elif isinstance(node, ast.Return):
                return True
            elif not isinstance(node, (ast.Expr, ast.Pass)):
                self.unexecuted_guards(node, env, scope, 'unsupported control flow: ' + type(node).__name__)
                self.invalidate(env, 'unsupported control flow: ' + type(node).__name__)

    def imports(self, node, env):
        for alias in node.names:
            if isinstance(node, ast.Import):
                env[alias.asname or alias.name] = MODULES.get(alias.name, Unknown('unsupported import: ' + alias.name))
            else:
                module = MODULES.get(node.module)
                env[alias.asname or alias.name] = (getattr(module, alias.name)
                    if module and alias.name in EXPORTS[node.module]
                    else Unknown('unsupported import: ' + str(node.module) + '.' + alias.name))
                if not module and alias.name in self.production:
                    self.production.add(alias.asname or alias.name)

    def helper(self, node):
        def call(*args, **kwargs):
            if node.args.defaults or node.args.vararg or node.args.kwarg or node.args.kwonlyargs or node.args.posonlyargs:
                raise Gap('helper argument defaults/variadics/keyword-only/positional-only unsupported')
            signature = inspect.Signature([inspect.Parameter(a.arg, inspect.Parameter.POSITIONAL_OR_KEYWORD)
                                           for a in node.args.args])
            bound = signature.bind(*args, **kwargs)
            env = dict(self.env)
            env.update(bound.arguments)
            for stmt in node.body:
                if isinstance(stmt, ast.Return):
                    return self.expression(stmt.value, env)
                if isinstance(stmt, ast.Assign):
                    value = self.expression(stmt.value, env)
                    for target in stmt.targets:
                        self.assign(target, value, env)
                else:
                    raise Gap('helper statement unsupported: ' + type(stmt).__name__)
            return None
        for decorator in reversed(node.decorator_list):
            expr = decorator.func if isinstance(decorator, ast.Call) else decorator
            try:
                fn = self.expression(expr, self.env)
            except Exception as exc:
                return Unknown(str(exc))
            if fn is not functools.lru_cache:
                return Unknown('unsupported decorator')
            if isinstance(decorator, ast.Call):
                args = [self.expression(a, self.env) for a in decorator.args]
                kw = {a.arg: self.expression(a.value, self.env) for a in decorator.keywords}
                call = functools.lru_cache(*args, **kw)(call)
            else:
                call = functools.lru_cache(call)
        self.allowed_helpers.append(call)
        return call

    def run(self, blocks):
        trees = []
        for index, code in enumerate(blocks, 1):
            try:
                tree = ast.parse(code)
            except SyntaxError as exc:
                self.checks.append({'id': f'python:block{index}', 'kind': 'parse',
                    'status': 'could-not-evaluate', 'expression': '', 'detail': str(exc)})
                continue
            trees.append((index, tree))
            for node in tree.body:
                if isinstance(node, (ast.Import, ast.ImportFrom)):
                    self.imports(node, self.env)
                if isinstance(node, ast.FunctionDef):
                    self.functions[node.name] = node
        for node in self.functions.values():
            if not node.name.startswith('test_') and node.name not in self.production:
                try:
                    self.env[node.name] = self.helper(node)
                except Exception as exc:
                    self.env[node.name] = Unknown(str(exc))
        for index, tree in trees:
            self.statements(tree.body, self.env, f'block{index}')
            for node in ast.walk(tree):
                if isinstance(node, ast.FunctionDef) and (node.name.startswith('test_') or node.name.endswith('_test')):
                    env = dict(self.env)
                    for arg in node.args.args:
                        env[arg.arg] = Unknown('pytest fixture not executed: ' + arg.arg)
                    self.statements(node.body, env, f'block{index}.{node.name}')
        return self.checks
