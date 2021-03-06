<?hh

function simple_function(): void {}
function simple_int_function(): int {
  return 5;
}
function simple_function_with_body(): float {
  return 0.5;
}

function function_with_args(int $arg1, float $arg2): void {}

type Typedef = string;
function function_with_non_primitive_args(Typedef $arg1): Typedef {
  return $arg1;
}

function test_generic_fun<T>(T $arg1): T {
  return $arg1;
}

function test_constrained_generic_fun<T1 super int, T2 as string>(
  T1 $arg1,
  T2 $arg2,
): T1 {
  return $arg1;
}

function test_returns_generic(): HH\Traversable<int> {
  return vec[5];
}

function takes_optional(?int $x): void {}

function in_out(inout int $x): void {}

function takes_returns_function_type<Tu>(
  Tu $x,
  (function(Tu): void) $unused,
): (function((function(Tu): void)): void) {
  return $x ==> {
    return;
  };
}

<<__Rx>>
function reactive_function(): void {}

<<__RxShallow>>
function shallow_reactive_function(): void {}

<<__RxLocal>>
function local_reactive_function(): void {}
