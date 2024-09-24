defmodule Evaluator do
  def eval(exp, env) do
    case Lexer.tokenize(exp) do
      {:ok, tokens} ->
        case Parser.parse(tokens) do
          {:ok, ast} ->
            eval_bop(ast)
          {:err, message} ->
            {:err, message}
        end
      {:illegal_char, char} ->
        {:err, "The character #{char} is not allowed in the expression"}
    end
  end
  defp eval_bop(ast) do
    case ast do
      {expr1, :ge, expr2} ->
        eval_
    end
  end
end
