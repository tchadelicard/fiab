defmodule Lexer do
  @moduledoc """
  The `Lexer` module is responsible for tokenizing a mathematical or logical expression.
  It converts an input string expression into a list of tokens that represent various
  operators, numbers, parentheses, and variables.

  The tokenizer supports:

  - Arithmetic operators: `+`, `-`, `*`, `/`
  - Parentheses: `(`, `)`
  - Comparison operators: `<`, `>`, `<=`, `>=`, `==`, `!=`
  - Numbers
  - Variables (composed of uppercase or lowercase letters)

  If an illegal character is encountered, the tokenizer will return an error in the form
  of `{:illegal_char, char}`.
  """

  # Define constants for various tokens
  @plus ?+
  @minus ?-
  @multiply ?*
  @divide ?/
  @space ?\s
  @open_parenthesis ?(
  @close_parenthesis ?)
  @equal ?=
  @less_than ?<
  @more_than ?>
  @exclam_mark ?!
  @numbers ?0..?9
  @uppercase_letters ?A..?Z
  @lowercase_letters ?a..?z

  @type token ::
          {:op, :add | :sub | :mul | :div | :eq | :lt | :le | :gt | :ge | :neq}
          | {:lparen}
          | {:rparen}
          | {:num, integer()}
          | {:var, String.t()}

  @spec tokenize(String.t()) :: [token] | {:illegal_char, String.t()}
  def tokenize(expression) do
    case next_token(expression |> String.to_charlist(), []) do
      {:ok, res} -> res
      {:illegal_char, char} -> {:illegal_char, char}
    end
  end

  # Recursively processes the character list to generate tokens
  @spec next_token([char()], [token]) :: {:ok, [token]} | {:illegal_char, String.t()}
  defp next_token([], tokens) do
    {:ok, tokens}
  end

  # Handling spaces
  defp next_token([@space | tail], tokens) do
    next_token(tail, tokens)
  end

  # Handling plus sign
  defp next_token([@plus | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :add}])
  end

  # Handling minus sign
  defp next_token([@minus | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :sub}])
  end

  # Handling multiply sign
  defp next_token([@multiply | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :mul}])
  end

  # Handling divide sign
  defp next_token([@divide | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :div}])
  end

  # Handling open parenthesis
  defp next_token([@open_parenthesis | tail], tokens) do
    next_token(tail, tokens ++ [{:lparen}])
  end

  # Handling close parenthesis
  defp next_token([@close_parenthesis | tail], tokens) do
    next_token(tail, tokens ++ [{:rparen}])
  end

  # Handling equal sign
  defp next_token([@equal | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :eq}])
  end

  # Handling less than sign (with optional equal for "less than or equal")
  defp next_token([@less_than, @equal | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :le}])
  end

  defp next_token([@less_than | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :lt}])
  end

  # Handling more than sign (with optional equal for "more than or equal")
  defp next_token([@more_than, @equal | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :ge}])
  end

  defp next_token([@more_than | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :gt}])
  end

  # Handling exclamation mark (with equal for "not equal")
  defp next_token([@exclam_mark, @equal | tail], tokens) do
    next_token(tail, tokens ++ [{:op, :neq}])
  end

  # Handling unexpected exclamation mark
  defp next_token([@exclam_mark | _tail], _tokens) do
    {:illegal_char, "!"}
  end

  # Handling numbers
  @spec next_token([char()], [token]) :: {:ok, [token]} | {:illegal_char, String.t()}
  defp next_token([char | tail], tokens) when char in @numbers do
    case get_number([char | tail], "") do
      {number, rest} ->
        next_token(rest, tokens ++ [{:num, number}])
    end
  end

  # Handling variables (uppercase and lowercase letters)
  @spec next_token([char()], [token]) :: {:ok, [token]} | {:illegal_char, String.t()}
  defp next_token([char | tail], tokens) when char in @uppercase_letters or char in @lowercase_letters do
    case get_variable([char | tail], "") do
      {variable, rest} ->
        next_token(rest, tokens ++ [{:var, variable}])
    end
  end

  # Handling unexpected characters
  @spec next_token([char()], [token]) :: {:ok, [token]} | {:illegal_char, String.t()}
  defp next_token([first | _tail], _tokens) do
    {:illegal_char, "#{[first] |> List.to_string()}"}
  end

  # Extracts a number from the input character list
  @spec get_number([char()], String.t()) :: {integer(), [char()]}
  defp get_number([], number_str) do
    {number_str |> String.to_integer(), []}
  end

  defp get_number([head | tail], number_str) when head in @numbers do
    get_number(tail, number_str <> List.to_string([head]))
  end

  defp get_number(rest, number_str) do
    {number_str |> String.to_integer(), rest}
  end

  # Extracts a variable from the input character list
  @spec get_variable([char()], String.t()) :: {String.t(), [char()]}
  defp get_variable([], variable_str) do
    {variable_str, []}
  end

  defp get_variable([head | tail], variable_str) when head in @numbers or head in @uppercase_letters or head in @lowercase_letters do
    get_variable(tail, variable_str <> List.to_string([head]))
  end

  defp get_variable(rest, variable_str) do
    {variable_str, rest}
  end
end
