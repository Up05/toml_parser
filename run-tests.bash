#!/usr/bin/env bash
# Also compatible with zsh, but not POSIX sh.
#
# Run the toml-test compliance tests: https://github.com/toml-lang/toml-test

# Decoder and encoder commands; leave encoder blank if writing TOML isn't supported.
decoder="./toml_parser"

encoder=  # No encoder tests

# Version of the TOML specification to test.
toml=1.1.0

# Skip known failures.
skip=(
	# Failing "valid" tests
	-skip 'valid/datetime/no-seconds'
	-skip 'valid/key/quoted-unicode'
	-skip 'valid/multibyte'
	-skip 'valid/spec-1.1.0/common-29'

	# Failing "invalid" tests
	-skip 'invalid/array/extend-defined-aot'
	-skip 'invalid/array/extending-table'
	-skip 'invalid/array/tables-01'
	-skip 'invalid/array/tables-02'
	-skip 'invalid/control/bare-cr'
	-skip 'invalid/control/comment-del'
	-skip 'invalid/control/multi-del'
	-skip 'invalid/control/rawmulti-del'
	-skip 'invalid/control/rawstring-del'
	-skip 'invalid/control/string-del'
	-skip 'invalid/datetime/offset-minus-minute-1digit'
	-skip 'invalid/datetime/offset-minus-no-hour-minute'
	-skip 'invalid/datetime/offset-minus-no-minute'
	-skip 'invalid/datetime/offset-plus-minute-1digit'
	-skip 'invalid/datetime/offset-plus-no-hour-minute'
	-skip 'invalid/datetime/offset-plus-no-minute'
	-skip 'invalid/datetime/second-trailing-dotz'
	-skip 'invalid/encoding/bad-codepoint'
	-skip 'invalid/encoding/bad-utf8-in-comment'
	-skip 'invalid/encoding/bad-utf8-in-multiline'
	-skip 'invalid/encoding/bad-utf8-in-multiline-literal'
	-skip 'invalid/encoding/bad-utf8-in-string'
	-skip 'invalid/encoding/bad-utf8-in-string-literal'
	-skip 'invalid/float/exp-dot-01'
	-skip 'invalid/float/leading-dot-neg'
	-skip 'invalid/float/leading-dot-plus'
	-skip 'invalid/float/trailing-exp'
	-skip 'invalid/float/trailing-exp-minus'
	-skip 'invalid/float/trailing-exp-plus'
	-skip 'invalid/inline-table/duplicate-key-03'
	-skip 'invalid/inline-table/duplicate-key-04'
	-skip 'invalid/inline-table/overwrite-02'
	-skip 'invalid/inline-table/overwrite-05'
	-skip 'invalid/inline-table/overwrite-06'
	-skip 'invalid/inline-table/overwrite-07'
	-skip 'invalid/inline-table/overwrite-08'
	-skip 'invalid/inline-table/overwrite-10'
	-skip 'invalid/integer/negative-bin'
	-skip 'invalid/integer/negative-hex'
	-skip 'invalid/integer/negative-oct'
	-skip 'invalid/integer/positive-bin'
	-skip 'invalid/integer/positive-hex'
	-skip 'invalid/integer/positive-oct'
	-skip 'invalid/key/bare-invalid-character-01'
	-skip 'invalid/key/bare-invalid-character-02'
	-skip 'invalid/key/dot'
	-skip 'invalid/key/dotted-redefine-table-01'
	-skip 'invalid/key/dotted-redefine-table-02'
	-skip 'invalid/key/escape'
	-skip 'invalid/key/multiline-key-01'
	-skip 'invalid/key/multiline-key-02'
	-skip 'invalid/key/multiline-key-03'
	-skip 'invalid/key/multiline-key-04'
	-skip 'invalid/key/partial-quoted'
	-skip 'invalid/key/special-character'
	-skip 'invalid/local-date/trailing-t'
	-skip 'invalid/spec-1.1.0/common-46-0'
	-skip 'invalid/spec-1.1.0/common-46-1'
	-skip 'invalid/spec-1.1.0/common-49-0'
	-skip 'invalid/string/bad-escape-02'
	-skip 'invalid/string/bad-escape-04'
	-skip 'invalid/string/bad-escape-05'
	-skip 'invalid/string/bad-multiline'
	-skip 'invalid/string/basic-multiline-out-of-range-unicode-escape-02'
	-skip 'invalid/string/basic-out-of-range-unicode-escape-02'
	-skip 'invalid/string/multiline-bad-escape-02'
	-skip 'invalid/string/multiline-bad-escape-03'
	-skip 'invalid/string/multiline-escape-space-01'
	-skip 'invalid/string/multiline-escape-space-02'
	-skip 'invalid/string/no-close-09'
	-skip 'invalid/string/no-close-10'
	-skip 'invalid/table/append-with-dotted-keys-01'
	-skip 'invalid/table/append-with-dotted-keys-02'
	-skip 'invalid/table/append-with-dotted-keys-03'
	-skip 'invalid/table/append-with-dotted-keys-04'
	-skip 'invalid/table/append-with-dotted-keys-06'
	-skip 'invalid/table/append-with-dotted-keys-07'
	-skip 'invalid/table/append-with-dotted-keys-08'
	-skip 'invalid/table/bare-invalid-character-01'
	-skip 'invalid/table/bare-invalid-character-02'
	-skip 'invalid/table/dot'
	-skip 'invalid/table/duplicate-key-01'
	-skip 'invalid/table/duplicate-key-04'
	-skip 'invalid/table/duplicate-key-05'
	-skip 'invalid/table/duplicate-key-07'
	-skip 'invalid/table/duplicate-key-09'
	-skip 'invalid/table/duplicate-key-10'
	-skip 'invalid/table/multiline-key-01'
	-skip 'invalid/table/multiline-key-02'
	-skip 'invalid/table/newline-02'
	-skip 'invalid/table/overwrite-with-deep-table'
	-skip 'invalid/table/redefine-02'
	-skip 'invalid/table/redefine-03'
	-skip 'invalid/table/super-twice'
)

# Find toml-test
tt=
if [[ -x "./toml-test" ]] && [[ ! -d "./toml-test" ]]; then
	tt="./toml-test"
elif command -v "toml-test" >/dev/null; then
	tt="toml-test"
elif [[ -n "$(go env GOBIN)" ]] && [[ -x "$(go env GOBIN)/toml-test" ]]; then
	tt="$(go env GOPATH)/toml-test"
elif [[ -n "$(go env GOPATH)" ]] && [[ -x "$(go env GOPATH)/bin/toml-test" ]]; then
	tt="$(go env GOPATH)/bin/toml-test"
elif [[ -x "$HOME/go/bin/toml-test" ]]; then
	tt="$HOME/go/bin/toml-test"
fi
if ! command -v "$tt" >/dev/null; then
	echo >&2 'toml-test not in current dir, $PATH, $GOBIN, $GOPATH/bin, or $HOME/go/bin; install with:'
	echo >&2 '    % go install github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0'
	echo >&2
	echo >&2 'Or download a binary from:'
	echo >&2 '    https://github.com/toml-lang/toml-test/releases'
	exit 1
fi


# Run toml-test
odin build .
echo >&2 "Running tests with: $tt"
"$tt" test -toml="$toml" -skip-must-err ${skip[@]} -decoder="$decoder" -encoder="${encoder:-}" "$@"
