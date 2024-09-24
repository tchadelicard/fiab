defmodule EvaluatorTest do
  use ExUnit.Case
  alias Evaluator

  @moduledoc """
  Test suite for the Evaluator module, covering arithmetic expressions, boolean comparisons,
  and error handling for division by zero and missing variables.
  """

  # Arithmetic Tests

  test "evaluate simple arithmetic expression" do
    assert Evaluator.eval("3 + 4 * 2", %{}) == {:ok, 11}
  end

  test "evaluate arithmetic with variables" do
    assert Evaluator.eval("x + 2 * y", %{"x" => 3, "y" => 4}) == {:ok, 11}
  end

  test "evaluate arithmetic with parentheses" do
    assert Evaluator.eval("(5 + 6) * 2", %{}) == {:ok, 22}
  end

  test "evaluate expression with variable addition" do
    assert Evaluator.eval("a + b", %{"a" => 2, "b" => 3}) == {:ok, 5}
  end

  # Boolean Comparison Tests

  test "evaluate greater than or equal (>=) comparison" do
    assert Evaluator.eval("x >= 3", %{"x" => 3}) == {:ok, true}
    assert Evaluator.eval("x >= 4", %{"x" => 3}) == {:ok, false}
  end

  test "evaluate greater than (>) comparison" do
    assert Evaluator.eval("x > 2", %{"x" => 3}) == {:ok, true}
    assert Evaluator.eval("x > 3", %{"x" => 3}) == {:ok, false}
  end

  test "evaluate less than or equal (<=) comparison" do
    assert Evaluator.eval("x <= 5", %{"x" => 5}) == {:ok, true}
    assert Evaluator.eval("x <= 3", %{"x" => 4}) == {:ok, false}
  end

  test "evaluate less than (<) comparison" do
    assert Evaluator.eval("x < 5", %{"x" => 3}) == {:ok, true}
    assert Evaluator.eval("x < 3", %{"x" => 3}) == {:ok, false}
  end

  test "evaluate equality (==) comparison" do
    assert Evaluator.eval("x = 3", %{"x" => 3}) == {:ok, true}
    assert Evaluator.eval("x = 4", %{"x" => 3}) == {:ok, false}
  end

  test "evaluate inequality (!=) comparison" do
    assert Evaluator.eval("x != 3", %{"x" => 3}) == {:ok, false}
    assert Evaluator.eval("x != 4", %{"x" => 3}) == {:ok, true}
  end

  # Error Handling Tests

  test "evaluate expression with division by zero" do
    assert Evaluator.eval("x / 0", %{"x" => 10}) == {:error, "Division by zero"}
  end

  test "evaluate expression with missing variable" do
    assert Evaluator.eval("x + z", %{"x" => 3}) == {:error, "Variable 'z' not found in the environment"}
  end

  test "evaluate expression with illegal character" do
    assert Evaluator.eval("3 + 4 & 2", %{}) == {:error, "Illegal character: &"}
  end
end
