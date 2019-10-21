# psu-monitor
Monitors PSU status via IPMI and sends notifications to slack


# TODO

Not all IPMI's return information in the same format, and some don't even 
return any information on the available PSU's and their status.

One major difference I have found is that some list the available PSU's like

	PS1 Status
	PS2 Status

Whereas some others list them as

	PS Status
	PS Status

Which means the awk script will need to be refactored.

Some other things that could be useful is a configuration file that sets
the values of the SLACK channels, etc, instead of depending on user to 
hard code in script files?

Alternate notification methods? e.g. email?