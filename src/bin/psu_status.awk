#!/bin/awk -f
# Output filter for: ipmitool sdr type 0x8
#
#
# We expect:
#       1   2            3 4   5 6   7 8     9 A        B
#               PS1 Status       | C8h | ok  | 10.88 | Presence detected
#               PS2 Status       | C9h | ok  | 10.87 | Presence detected


BEGIN {

        seen1=0
        ok1=0
        ok2=0
        detected1=0
        detected2=0
        seen2=0

}

/PS1 Status/ { seen1=1; if("ok"==$6) ok1=1; if("detected"==$11) detected1=1; }
/PS2 Status/ { seen2=1; if("ok"==$6) ok2=2; if("detected"==$11) detected2=1; }


END {

        if(!seen1 && !seen2) { print "ALL_PSU_MISSING"; exit 2; }
        if(seen1 && !seen2)  { print "PSU_ONE_MISSING"; exit 2; }
        if(!seen1 && seen2)  { print "PSU_TWO_MISSING"; exit 2; }

        if(!ok1 && !ok2)     { print "ALL_PSU_BAD"; exit 3; }
        if(!ok1 && ok2)      { print "PSU_ONE_BAD"; exit 3; }
        if(ok1 && !ok2)      { print "PSU_TWO_BAD"; exit 3; }

        if(!detected1 && !detected2) { print "ALL_PSU_ERROR"; exit 4; }
        if(detected1 && !detected2)  { print "PSU_TWO_ERROR" ; exit 4; }
        if(!detected1 && detected2)  { print "PSU_ONE_ERROR" ; exit 4; }

        if(seen1 && seen2 && ok1 && ok2 && detected1 && detected2) {

                print "OK"

                exit 0;
        }

        print "UNKNOWN_ERROR";

        exit 1
}

