defmodule ParserTest do
  use ExUnit.Case
  alias Parser

  @moduledoc """
  Test suite for the Parser module.
  """

  # Positive Tests

  test "parse simple addition" do
    tokens = [
      {:num, 3},
      {:op, :add},
      {:num, 4}
    ]
    expected_ast = {{:num, 3}, :add, {:num, 4}}
    assert Parser.parse(tokens) == {:ok, expected_ast}
  end

  test "parse multiplication and addition" do
    tokens = [
      {:num, 3},
      {:op, :add},
      {:num, 4},
      {:op, :mul},
      {:num, 2}
    ]
    expected_ast = {{:num, 3}, :add, {{:num, 4}, :mul, {:num, 2}}}
    assert Parser.parse(tokens) == {:ok, expected_ast}
  end

  test "parse expression with parentheses" do
    tokens = [
      {:lparen},
      {:num, 5},
      {:op, :add},
      {:num, 6},
      {:rparen},
      {:op, :mul},
      {:num, 2}
    ]
    expected_ast = {{{:num, 5}, :add, {:num, 6}}, :mul, {:num, 2}}
    assert Parser.parse(tokens) == {:ok, expected_ast}
  end

  test "parse comparison operators" do
    tokens = [
      {:var, "x"},
      {:op, :ge},
      {:num, 10}
    ]
    expected_ast = {{:var, "x"}, :ge, {:num, 10}}
    assert Parser.parse(tokens) == {:ok, expected_ast}
  end

  # Negative Tests

  test "parse with unmatched parentheses" do
    tokens = [
      {:lparen},
      {:num, 5},
      {:op, :add},
      {:num, 6}
    ]
    assert Parser.parse(tokens) == {:err, "Expected a right parenthesis"}
  end

  test "parse with unexpected token" do
    tokens = [
      {:num, 3},
      {:op, :add},
      {:lparen}
    ]
    assert Parser.parse(tokens) == {:err, "Unexpected end of input"}
  end

  test "parse with missing operator" do
    tokens = [
      {:num, 3},
      {:num, 4}
    ]
    assert Parser.parse(tokens) == {:err, "Unexpected number without an operator between expressions"}
  end

  test "parse multiple variables with missing operator" do
    tokens = [
      {:var, "a"},
      {:var, "b"}
    ]
    assert Parser.parse(tokens) == {:err, "Unexpected variable without an operator between expressions"}
  end
end
