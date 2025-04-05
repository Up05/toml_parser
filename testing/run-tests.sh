#!/usr/bin/env bash

cd "$(dirname "$0")"

if [ ! -f ./toml-test ]; then 
    echo "========== INSTALLING TESTING SOFTWARE =========="
    export GOBIN=/tmp
    go install github.com/toml-lang/toml-test/cmd/toml-test@v1.5.0 || ( echo "Failed to install /tmp/toml-test"; exit 1 )
    mv /tmp/toml-test ./toml-test || ( echo "Failed to move /tmp/toml-test to ./toml-test"; exit 1 )
fi

cd ..
md5sum -c testing/no-needless-comp.txt &> /dev/null || (
    echo "========== COMPILING TOML PARSER =========="
    odin build . -use-separate-modules -lld -o:none -show-timings -out:testing/parser || ( echo "Toml parser compilation failed"; exit 1 )
    md5sum *.odin > testing/no-needless-comp.txt
)
cd -

echo "========== RUNNING SELECTED TESTS =========="
selection=$(./toml-test -list-files | grep -vf unwanted-tests | tac | fzf)
./toml-test ./parser -timeout 10s -run "${selection//.toml}"


# You might need to install fzf and go
