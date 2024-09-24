defmodule Evaluator do
  @moduledoc """
  The `Evaluator` module evaluates mathematical and logical expressions with variables.
  It takes an expression as a string, tokenizes and parses it, then evaluates the result
  using the values provided in the `env` map.

  If a variable in the expression is not found in the environment (`env`), it returns
  an error.
  """

  alias Lexer
  alias Parser

  @doc """
  Evaluates a given expression using the variable values provided in `env`.

  ## Parameters
    - `expression`: A string containing a mathematical expression to evaluate.
    - `env`: A map of variables and their corresponding values.

  ## Returns
    - `{:ok, result}`: The result of the evaluated expression.
    - `{:err, message}`: An error message if evaluation fails.

  ## Examples

      iex> Evaluator.eval("x + 2 * y", %{"x" => 3, "y" => 4})
      {:ok, 11}

      iex> Evaluator.eval("x + z", %{"x" => 3})
      {:err, "Variable 'z' not found in the environment"}

  """
  def eval(expression, env) do
    case Lexer.tokenize(expression) do
      {:illegal_char, char} ->
        {:err, "Illegal character: #{char}"}
      tokens ->
        case Parser.parse(tokens) do
          {:err, message} ->
            {:err, message}
          {:ok, ast} ->
            evaluate(ast, env)
        end
    end
  end

  # Evaluates the abstract syntax tree (AST)
  defp evaluate({left, op, right}, env) do
    case evaluate(left, env) do
      {:ok, left_val} ->
        case evaluate(right, env) do
          {:ok, right_val} ->
            apply_operator(left_val, op, right_val)
          {:err, _} = error -> error
        end
      {:err, _} = error -> error
    end
  end

  defp evaluate({:num, value}, _env) do
    {:ok, value}
  end

  defp evaluate({:var, name}, env) do
    case Map.fetch(env, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:err, "Variable '#{name}' not found in the environment"}
    end
  end

  # Applies arithmetic and comparison operations
  defp apply_operator(left, :add, right) do
    {:ok, left + right}
  end

  defp apply_operator(left, :sub, right) do
    {:ok, left - right}
  end

  defp apply_operator(left, :mul, right) do
    {:ok, left * right}
  end

  defp apply_operator(left, :div, right) do
    if right == 0 do
      {:err, "Division by zero"}
    else
      {:ok, div(left, right)}
    end
  end

  # Comparison operators with real boolean return values
  defp apply_operator(left, :ge, right) do
    if left >= right do
      {:ok, true}
    else
      {:ok, false}
    end
  end

  defp apply_operator(left, :gt, right) do
    if left > right do
      {:ok, true}
    else
      {:ok, false}
    end
  end

  defp apply_operator(left, :le, right) do
    if left <= right do
      {:ok, true}
    else
      {:ok, false}
    end
  end

  defp apply_operator(left, :lt, right) do
    if left < right do
      {:ok, true}
    else
      {:ok, false}
    end
  end

  defp apply_operator(left, :eq, right) do
    if left == right do
      {:ok, true}
    else
      {:ok, false}
    end
  end

  defp apply_operator(left, :neq, right) do
    if left != right do
      {:ok, true}
    else
      {:ok, false}
    end
  end
end
