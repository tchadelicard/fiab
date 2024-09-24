defmodule LexerTest do
  use ExUnit.Case
  alias Lexer

  @moduledoc """
  Test suite for the Lexer module.
  """

  # Positive Tests

  test "tokenize simple arithmetic expression" do
    expression = "3 + 4 * 2"
    tokens = [
      {:num, 3},
      {:op, :add},
      {:num, 4},
      {:op, :mul},
      {:num, 2}
    ]
    assert Lexer.tokenize(expression) == tokens
  end

  test "tokenize expression with parentheses" do
    expression = "(5 + 6) * 2"
    tokens = [
      {:lparen},
      {:num, 5},
      {:op, :add},
      {:num, 6},
      {:rparen},
      {:op, :mul},
      {:num, 2}
    ]
    assert Lexer.tokenize(expression) == tokens
  end

  test "tokenize comparison operators" do
    expression = "x >= 10"
    tokens = [
      {:var, "x"},
      {:op, :ge},
      {:num, 10}
    ]
    assert Lexer.tokenize(expression) == tokens
  end

  test "tokenize variable names and numbers" do
    expression = "x1 + y2"
    tokens = [
      {:var, "x1"},
      {:op, :add},
      {:var, "y2"}
    ]
    assert Lexer.tokenize(expression) == tokens
  end

  # Negative Tests

  test "tokenize with illegal character" do
    expression = "5 + &"
    assert Lexer.tokenize(expression) == {:illegal_char, "&"}
  end

  test "tokenize incomplete expression" do
    expression = "3 + "
    assert Lexer.tokenize(expression) == [
      {:num, 3},
      {:op, :add}
    ]
  end

  test "tokenize with unsupported operator" do
    expression = "4 % 2"
    assert Lexer.tokenize(expression) == {:illegal_char, "%"}
  end
end
