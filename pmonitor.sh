#!/bin/sh
#
# Monitor the progress of a specified job
#
# Copyright 2006-2018 Diomidis Spinellis
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# For each file or file associated with the specified process is reading,
# display the percentage associated with its seek pointer offset.  For
# files that are processed in a sequential fashion this can be translated
# to the percentage of the job that has been completed.
#
# This command is modelled after a similar facility
# available on Permin-Elmer/Concurrent OS32
#
# Requires:
# - lsof(8) with offset (-o) printing functionality
#
# Submit issues and pull requests as https://github.com/dspinellis/pmonitor
#

# Run lsof with the specified options
# The OPT1 and OPT2 variables are passed to lsof as arguments.
opt_lsof()
{
  lsof -w -o0 -o "$OPT1" "$OPT2"
}

# Display the scanned percentage of lsof files.
display()
{
  # Obtain the offset and print it as a percentage
  awk '
    # Return current time
    function time() {
	"date +%s" | getline t
	close("date +%s")
	return t
    }

    # Return length of specified file
    function file_length(fname) {
      if (!cached_length[fname]) {
	"ls -l '\''" fname "'\'' 2>/dev/null" | getline
	cached_length[fname] = $5 + 0
      }
      return cached_length[fname]
    }

    BEGIN {
      CONVFMT = "%.2f"
      start = time()
    }

    $4 ~ /^[0-9]+[r'$UPDATE']$/ && $7 ~ /^0t/ {
      now = time()
      offset = substr($7, 3)
      fname = $9
      len = file_length(fname)
      if (len > 0) {
	if (!start_offset[fname])
	  start_offset[fname] = offset
	delta_t = now - start
	delta_o = offset - start_offset[fname]
	if (delta_t > 5 && delta_o > 0) {
	  bps = delta_o / delta_t
	  t = (len - offset) / bps
	  eta_s = t % 60
	  t = int(t / 60)
	  eta_m = t % 60
	  t = int(t / 60)
	  eta_h = t
	  eta = sprintf("ETA %d:%02d:%02d", eta_h, eta_m, eta_s)
	}
        print fname, offset / len * 100 "%", eta
      }
    }
  '
}

# Report program usage information
usage()
{
	cat <<\EOF 1>&2
Usage:

pmonitor [-c command] [-f file] [-i interval] [-p pid]
-c, --command=COMMAND	Monitor the progress of the specified running command
-f, --file=FILE		Monitor the progress of commands processing the
			specified file
-h, --help		Display this message and exit
-i, --interval=INTERVAL	Continuously display the progress every INTERVAL seconds
-p, --pid=PID		Monitor the progress of the process with the specified
			process id
-u, --update		Also monitor files opened in update (rather than read
			mode)

Exactly one of the c, f, p options must be specified.

Terminating...
EOF
}

# Option processing; see /usr/share/doc/util-linux-ng-2.17.2/getopt-parse.bash
# Note that we use `"$@"' to let each command-line parameter expand to a
# separate word. The quotes around `$@' are essential!
# We need TEMP as the `eval set --' would nuke the return value of getopt.

# Allowed short options
SHORTOPT=c:,f:,h,i:,p:,u

if getopt -l >/dev/null 2>&1 ; then
  # Simple (e.g. FreeBSD) getopt
  TEMP=$(getopt $SHORTOPT "$@")
else
  # Long options supported
  TEMP=$(getopt -o $SHORTOPT --long command:,file:,help,interval:,pid:,update -n 'pmonitor' -- "$@")
fi

if [ $? != 0 ] ; then
  usage
  exit 2
fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while : ; do
  case "$1" in
    -c|--command)
      OPT1=-c
      OPT2="$2"
      shift 2
      ;;
    -f|--file)
      OPT1=--
      OPT2="$2"
      shift 2
      ;;
    -i|--interval)
      INTERVAL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -p|--pid)
      OPT1=-p
      OPT2="$2"
      shift 2
      ;;
    -u|--update)
      UPDATE=u
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Internal error!"
      exit 3
      ;;
  esac
done

# No more arguments allowed and one option must be specified
if [ "$1" != '' -o ! -n "$OPT1" -o ! -n "$OPT2" ]
then
  usage
  exit 2
fi

if [ "$INTERVAL" ] ; then
  while : ; do
    opt_lsof
    sleep $INTERVAL
  done
else
  opt_lsof
fi |
display
