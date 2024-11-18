# get dependencies
deps:
	mix deps.get
	mix deps.compile

compile: deps
	mix compile

# run
run: deps compile clean
	iex -S mix

setup_notebook:
	pip3 install matplotlib
	pip3 install pandas

# open notebook
notebook:
	jupyter notebook simulation_analysis.ipynb

setup_livebook:
	mix do local.rebar --force, local.hex --force
	mix escript.install hex livebook
	asdf reshim elixir

livebook:
	livebook server simulation_analysis.livemd

# clean
clean:
	rm -rf data/*
