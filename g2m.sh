#!/bin/bash
#
# g2m.sh
#
# Purpose: 
#   create a matlab/octave file from 3D-printer CAM code: G-code to Matlab converter.
#
# Usage examples:
#
#  g2m.sh      # copy latest g-file in local directory
#
#  g2m.sh -h               # show help
#  g2m.sh -t               # test run, output to *.mecho
#  g2m.sh -d -l -e XXX.g   # output debug info and linenumbers, relative extrusion rate 
#  g2m.sh *.g  # process all g-code files
#  
#  g2m.sh key=val *.g      # use long options, see source code for recognized keys.
#
# Background:
#   - analyse what the slicer does, study fill patterns with the goal to replace them
#   - you can pick interesting sections and cut&paste them to GNU octave. 
#   - currently only tested with curabydago
#   - we rely on the strucutre of some comments in the g-code file.
#   - g-code doc: https://reprap.org/wiki/G-code/de#G0_.26_G1:_Move
#   - the last point of the previous trajectory will be repeated at the beginning
#     and marked with a f-value of -1
#   - m2g.sh yet to come...
#
# $Header: g2m.sh, v0.2, Andreas Merz, 2019-02-01 $
# GPLv3 or later, see http://www.gnu.org/licenses

#-------- create simple test structures ------
## T.scad
# txt="T";
# fontname = "Liberation Sans";
# fontsize = 5;
#   translate([0,0,0]) linear_extrude(height = 0.4) 
#   text(txt, size = fontsize, font = fontname, halign = "center", valign = "center", $fn = 16);

## Q.scad
# cube(size = [10, 12, 5]);
#
# use Cura to create g-file.
#--------------------------------------------

hc=cat

#--- default settings ---
gext=dagoma0.g      # g-file file name extension for SD-card print target
gfile=$(ls -1tr *.g | tail -n 1)  # take latest g-file in actual directory
header="% $USER@$HOSTNAME $(date  '+%F %T')"     # add a header to matlab file
debug=0                           # option: debug level in output
lnum=0                            # option: no line numbers in output
extrusionrate=0                   # option: output extrusion rate instead of accumulated length

#--- process arguments ---
cmdline="$0 $@"
narg=$#
echo=echo
cnt=0

while [ "$1" != "" ] ; do
  case "$1" in
   -h)       sed -n '2,/^#.*Header: /p' $0 | cut -c 2- ; exit ;;   # help
   -t)       t=echo ; echo="echo -ne \\c" ;;  # dry run, test
   -d)       debug=1 ;;            # debug level
   -e)       extrusionrate=1 ;;    # extrusion rate output
   -l)       lnum=1 ;;             # add line numbers
   -*)       echo "warning: unknown option $1" ;  sleep 2 ;;
   *=*)      echo $1 | $hc ; eval $1 ;;
   *)        par="$1" ; cnt=`expr $cnt + 1` ; echo "arg[$cnt]=$par" | $hc ;;
  esac
  shift

  # compatibility to enumerated parameter interface  - no mixing, only appending of new will work!
  case "$cnt" in 
   0)  ;; 
   1)  gfile="$par" ; gfiles="$gfile" ;;
   *)  gfiles="$gfiles $par" ;;             # append all further arguments
  esac 
done


# show settings
varlist="$(sed -ne "/^#--- default settings ---/,/^#--- process arguments ---/p" $0 | grep "=" | grep -v "^if " | grep -v "^ *echo "  | sed -e 's/=.*//' -e 's/^ *//' | grep -v "#" | sort -u )"
#echo $varlist
echo                    | $hc
echo "# command line:"  | $hc
echo "$cmdline"         | $hc
echo                    | $hc
echo "# settings:"      | $hc
for vv in $varlist ; do
  echo "$vv=\"${!vv}\"" | $hc
done                    
echo                    | $hc

if [ "$gfiles" == "" ] ; then
  gfiles=$gfile
fi

#-------------------------------------------------
# convert g-code loop
#-------------------------------------------------

for ii in $gfiles ; do
  mfile=$(echo $ii | sed -e "s/\.$gext//").m$t
  echo "# converting $ii to $mfile"
  rm -f $mfile
  if [ "$header" ] ; then
    echo -e "% matlab/octave file\n$header\n% $cmdline\n% $ii -> $mfile\n%" >> $mfile
  fi

  cat $ii |
  awk -v opt_debug=$debug -v opt_lnum=$lnum -v opt_extrusionrate=$extrusionrate '
           {
             if(opt_lnum) comment=sprintf("%%%5d: %s",FNR,$0);   # add line number of current file
             else         comment=sprintf("%%%s",$0);
           }

  /LAYER:/ { split($0, val, "LAYER:", key);
             nold=n;
             typeshortold=typeshort;
             typeshort="";
             n=val[2];    # Layer number
             flushmat++;
           }

  /TYPE:/  { split($0, val, "TYPE:",  key); 
             typeshortold=typeshort;  # FIFO 2
             nold=n; 
             type=val[2];
             switch(type) {
               case /SKIN/:       typeshort="sn"; break;
               case /SKIRT/:      typeshort="st"; break;
               case /WALL-INNER/: typeshort="wi"; break;
               case /WALL-OUTER/: typeshort="wo"; break;
               case /FILL/:       typeshort="fi"; break;
               default:           typeshort="";   break;
             }
             flushmat=2;
           }

  /M84/    { flushmat=3;   # Shut down at end
             typeshortold=typeshort;
           }

  /^G[01]/ { split($0, val, " *[XYZEF;]", key);
             
             # parse arguments of G1 and G0 message
             for(i=1; key[i]!="" ; i++) { 
               #print "%" key[i] "=" val[i+1];  # debug output
               switch( key[i] ) {
                 case /X/: Xnew=val[i+1]; break;
                 case /Y/: Ynew=val[i+1]; break;
                 case /Z/: Znew=val[i+1]; break;
                 case /E/: Enew=val[i+1]; break;
                 case /F/: Fnew=val[i+1]; break;
                 case /;/: Cnew=val[i+1]; key[i+1]=""; break;
                 default: print "syntax error: unknown" key[i];
               }
             }
             distold=dist;
             rextrusionold=rextrusion;
             dist=sqrt((Xnew-Xold)^2 + (Ynew-Yold)^2 + (Znew-Zold)^2);
             if(dist>0) rextrusion=(Enew-Eold)/dist;
             else rextrusion=0;

             extrusion=Enew;
             if(opt_extrusionrate) extrusion=rextrusion;
             
             # append new values to vectors:
             xx=sprintf("%s %8.3f", xx, Xnew);
             yy=sprintf("%s %8.3f", yy, Ynew);
             zz=sprintf("%s %8.3f", zz, Znew);
             dd=sprintf("%s %8.3f", dd, dist);
             ff=sprintf("%s %8d",   ff, Fnew);
             ee=sprintf("%s %8.3f", ee, extrusion);

             # FIFO 2 for distance calculation
             Xold=Xnew; Yold=Ynew; Zold=Znew; Eold=Enew; Fold=Fnew; 
             # omit comments for the normal moves
             if(opt_debug==0) comment="";
           }
           
           { 
             if(flushmat >= 2 && (typeshortold != "" || n==0) ) {
               # matlab variable number + extension
               v=sprintf("%d%s",nold,typeshortold);

               # output matlab code
               printf("x%s=[%s];\n",v,xx);
               printf("y%s=[%s];\n",v,yy);
               printf("z%s=[%s];\n",v,zz);
               printf("d%s=[%s];\n",v,dd);
               printf("e%s=[%s];\n",v,ee);
               printf("f%s=[%s];\n",v,ff);
               printf("plot3( x%s,y%s,z%s, %cLineWidth%c, 2); grid on; hold on;\n",v,v,v, 39, 39);
               
               # clear vectors, init with last value
               xx=sprintf("%8.3f", Xnew);
               yy=sprintf("%8.3f", Ynew);
               zz=sprintf("%8.3f", Znew);
               dd=sprintf("%8.3f", 0);
               ff=sprintf("%8d",  -1);
               ee=sprintf("%8.3f", Enew);
               if(opt_extrusionrate) ee=sprintf("%8.3f", 0);

               flushmat=1;  # flag flushing done
             }
             if(comment!="") print comment;
           }
           ' >> $mfile

done
