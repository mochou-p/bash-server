#!/usr/bin/env bash

# bash-server/server.sh

# TODO:
#   netstat -> ss?
#   check for GET method
#   send Content-Type so all browsers render HTML
#   send proper responses (status codes, headers)
#   serve `<a>`s from dirs
#   concurrent connections

# disable stdin echo
stty -echo

# get the CLI argument
arg="$@"
if [[ "${arg}" == "" ]]; then
    echo -e "\x1b[31;1merror:\x1b[0m provide a port argument"
    echo "       example: \`$0 42069\`"
    stty echo
    exit 1;
fi

# make sure there is only one argument
if echo -n "${arg}" | grep -q " "; then
    echo -e "\x1b[31;1merror:\x1b[0m provide only one port argument"
    echo "       example: \`$0 42069\`"
    stty echo
    exit 1;
fi

# make sure the argument is a number
if !(printf "%d" "${arg}" &> /dev/null); then
    echo -e "\x1b[31;1merror:\x1b[0m \`${arg}\` is not a number"
    stty echo
    exit 1;
fi

# make sure the number is outside the well-known range
if (( "${arg}" < 1024 || "${arg}" > 65535 )); then
    echo -e "\x1b[31;1merror:\x1b[0m use a port in range 1024..=65535"
    stty echo
    exit 1;
fi

# check if port is already in use
out=$(netstat -atulnp 2> /dev/null | awk -v ARG="${arg}" '$4 ~ ":" ARG "$" && $6 == "LISTEN"')
if echo -n "${out}" | grep -q .; then
    out=$(echo -n "${out}" | awk '{print $7}' | awk -F '/' '{print "`"$2"` (PID "$1")"}')
    echo -e "\x1b[31;1merror:\x1b[0m port ${arg} is already in use by ${out}"
    stty echo
    exit 1;
fi

client_pipe="/tmp/client_fd"

# create a client pipe on the filesystem
mkfifo "${client_pipe}" 2> /dev/null

# custom Ctrl+C handler to handle cleanup
trap 'echo -e "> server stopped\x1b[0m"; stty echo; kill -s STOP "${server_pid}"; rm "${client_pipe}"; trap - SIGINT' SIGINT

echo -e "\x1b[32;1m> server is running on \`localhost:${arg}\`\x1b[0m"
echo -e "\x1b[33;1m> Ctrl+C to stop the server\x1b[31;1m"

(
    # loop forever
    while [[ true ]]; do
        # read the client request
        # extract the start line   e.g. "GET /index.html HTTP/1.1"
        # extract the target       e.g. "/index.html"
        # skip the first character e.g. "index.html"
        cat "${client_pipe}"        \
        | head -1                    \
        | awk '{print $2}'            \
        | awk '{print substr($1,2); }' \
        | {
            # TODO: clean up this grouping
            filename=$(cat -)

            if [[ "${filename}" == "" ]]; then
                out=$(ls)

                if [[ "${out}" == "" ]]; then
                    echo -e "\x1b[0m[\x1b[32;1m       ok\x1b[0m] /${filename}\x1b[31;1m" > /dev/tty
                    echo "empty dir";
                else
                    echo -e "\x1b[0m[\x1b[32;1m       ok\x1b[0m] /${filename}\x1b[31;1m" > /dev/tty
                    echo "${out}";
                fi;
            elif [[ -d "${filename}" ]]; then
                out=$(ls "${filename}");

                if [[ "${out}" == "" ]]; then
                    echo -e "\x1b[0m[\x1b[32;1m       ok\x1b[0m] /${filename}\x1b[31;1m" > /dev/tty
                    echo "empty dir";
                else
                    echo -e "\x1b[0m[\x1b[32;1m       ok\x1b[0m] /${filename}\x1b[31;1m" > /dev/tty
                    echo "${out}";
                fi;
            elif [[ -f "${filename}" ]]; then
                echo -e "\x1b[0m[\x1b[32;1m       ok\x1b[0m] /${filename}\x1b[31;1m" > /dev/tty
                if [[ -s "${filename}" ]]; then
                    cat "${filename}";
                else
                    echo "empty file";
                fi;
            else
                echo -e "\x1b[0m[\x1b[31;1mnot found\x1b[0m] /${filename}\x1b[31;1m" > /dev/tty
                echo "not found";
            fi;

        # pipe the response back into the server and redirect to client
        } | nc -N -l "${arg}" > "${client_pipe}";
    done

# run in the background, and save the server PID
) & server_pid="$!"

# wait for the server to die (killed in the SIGINT handler)
wait "${server_pid}"

