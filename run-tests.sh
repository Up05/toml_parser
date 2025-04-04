# You might need to install fzf and go

if [ ! -f ./toml-test ]; then 
    echo "========== INSTALLING TESTING SOFTWARE =========="
    export GOBIN=/tmp
    go install github.com/toml-lang/toml-test/cmd/toml-test@v1.5.0
    mv /tmp/toml-test ./toml-test
fi

md5sum -c no-needless-comp.txt > /dev/null || (
    echo "========== COMPILING TOML PARSER =========="
    odin build . -use-separate-modules -lld -o:speed -show-timings
    md5sum *.odin > no-needless-comp.txt
)

echo "========== RUNNING SELECTED TESTS =========="
selection=$(./toml-test -list-files | fzf)
./toml-test ./toml_parser -timeout 10s -run "${selection//.toml}"




# "md5sum: no-needless-comp.txt: No such file or directory" Is perfectly fine
