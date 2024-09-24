# Homework 1

This Elixir project implements a simple expression evaluator. The project contains three main modules: `Lexer`, `Parser`, and `Evaluator`. The `Lexer` tokenizes expressions, the `Parser` parses these tokens into an Abstract Syntax Tree (AST), and the `Evaluator` computes the result of the expression based on the parsed AST and the provided environment.

## Project Structure

```
├── README.md                 # Project documentation
├── lib/                      # Source files for Lexer, Parser, and Evaluator
│   ├── evaluator.ex          # Evaluates expressions with variables and arithmetic
│   ├── lexer.ex              # Tokenizes input strings
│   └── parser.ex             # Parses tokens into an AST
├── mix.exs                   # Mix project file
└── test/                     # Unit tests for each module
    ├── evaluator_test.exs    # Tests for Evaluator module
    ├── lexer_test.exs        # Tests for Lexer module
    ├── parser_test.exs       # Tests for Parser module
    └── test_helper.exs       # Test helper
```

## Usage

### 1. Run the project in iex

You can use the project interactively by launching the Elixir shell (iex):

```
iex -S mix
```

Now, you can evaluate expressions using the Evaluator module:

```
# Simple arithmetic with variables
Evaluator.eval("x + 2 * y", %{"x" => 3, "y" => 4})
# {:ok, 11}

# Comparison operations
Evaluator.eval("x >= 3", %{"x" => 3})
# {:ok, true}

# Error when dividing by zero
Evaluator.eval("10 / 0", %{})
# {:error, "Division by zero"}

# Error when a variable is missing
Evaluator.eval("x + z", %{"x" => 3})
# {:error, "Variable 'z' not found in the environment"}
```

### 2. Run unit tests

The project includes unit tests for the `Lexer`, `Parser`, and `Evaluator` modules.

To run the tests, use the following command:

```
mix test
```

This will execute all the test cases in the `test/` directory and display the results.

## Credits

Module documentation and README created with the assistance of ChatGPT.
