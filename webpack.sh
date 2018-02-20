#!/bin/bash
#
# WebPack 0.7 beta Copyright (C) 2004-2018 Errol Smith / Kludgesoft
#
# webpack on the web - http://www.kludgesoft.com/nix/webpack.html
#
# contact webpack author - ezza (at) kludgesoft [dot] com
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#    Or see http://www.gnu.org/licenses/gpl.html
#
# What is it?
#
# A simple script to do useful browser-lossless(*) compression of different
# types of files commonly found on websites.
#
# Requires at least one (preferably all) of the following:
# - jpegtran - processes jpeg images
# - gifsicle OR giftrans - processes gif images (gifsicle preferred)
# - pngcrush - processes png images
# - htmlcrunch OR HTML::Clean - compresses html files
# - advancecomp - recompresses gz, zip & png files
#
# * - pictures are pixel-for-pixel identical, they just dont have lots of
# useless crap like comments, preview icons etc. Compression is also optimised
# html has comments/whitespace removed
# 


filecount=0
failurecount=0
skipcount=0
dircount=0
ifilebytes=0
ofilebytes=0
#filesize counters for input
ibytes=0
ihtmbytes=0
ipngbytes=0
igifbytes=0
ijpgbytes=0
iothbytes=0
#filesize counters for output
obytes=0
ohtmbytes=0
opngbytes=0
ogifbytes=0
ojpgbytes=0
oothbytes=0


# Process options
if [ ! "$*" ]
then
    echo ""
    echo "WebPack 0.6a beta - Copyright 2004-2018 Errol Smith / Kludgesoft"
    echo "This program processes files recursively from the current directory"
    echo "and outputs a processed copy to <outdir>"
    echo "Usage: webpack [options] outdir"
    echo "Options: -b   Brute force (try more methods at expense of some speed)"
    echo "         -f   Force overwrite of existing files in target directory (use with caution!)"
    echo "         -q   Quiet mode (show only errors)"
    echo "         -u   Update (replace files if source newer than target)"
    echo "eg: ~/mysite> webpack -bu ~/mysitepacked"
    echo ""
    exit 0
fi

while getopts "bfqu" option
do
    case $option in
    	b)  brute="-brute" ; brute4="4"; bruteoptipng="-o 9" ;;
        f)  force="force" ;;
        q)  quiet="quiet" ;;
        u)  update="update" ;;
        \?) errors=1 ;;
    esac
done
shift $(($OPTIND - 1))

if [ ! $quiet ]; then
    if [ $brute ]; then echo "Brute option specified (-b)"; fi
    if [ $force ]; then echo "Force overwrite option specified (-f)"; fi
    if [ $update ]; then echo "Update option specified (-u)"; fi
fi

if [ $errors ]
then
    echo "Unknown option(s) on command line, exiting.."
    exit 1
fi

outdir=$1       # output directory is first non-option argument
if [ ! "$outdir" ]
then
    echo "ERROR - no output directory specified.."
    exit 1
fi



# Test if the programs we need are installed

htmtest=$(which htmlclean 2> /dev/null)
if [ $htmtest ]
then
    htmtest=2
    #echo "HTML::Clean installed"
else
	echo "htmlclean not installed, html will not be processed"
fi


giftest=$(which gifsicle 2> /dev/null)
if [ $giftest ]
then
    giftest=2
    #echo "gifsicle installed"
else
    giftest=$(which giftrans 2> /dev/null)
    if [ $giftest ]
    then
        #echo "giftrans installed"
        giftest=1
    else
        echo "neither gifsicle (preferred) or giftrans installed, gifs will not be processed"
    fi
fi


jpgtest=$(which jpegtran 2> /dev/null)
if [ ! $jpgtest ]
then
    echo "jpegtran not installed, jpegs will not be processed"
fi

pngtest=$(which optipng 2> /dev/null)
if [ $pngtest ]
then
    pngtest=2
    echo "OptiPNG installed"
else
    pngtest=$(which pngcrush 2> /dev/null)
    if [ $pngtest ]
    then
        echo "pngcrush installed"
    else
        echo "neither OptiPNG (preferred) or pngcrush installed, pngs will not be processed"
    fi
fi

bz2test=$(which bzip2 2> /dev/null)
#if [ ! $bz2test ]
#then
#    echo "bzip2 not installed, bz2 files will not be processed"
#fi

#test for advancecomp utils
advdeftest=$(which advdef 2> /dev/null)
advziptest=$(which advzip 2> /dev/null)
#if [ ! $advdeftest ]
#then
#    echo "advcomp not installed, gz, zip & (maybe) png will not be processed"
#fi


if [ $htmtest ] || [ $giftest ] || [ $jpgtest ] || [ $pngtest ] ; then :
else
    echo "Nothing I need is installed - failing"
    echo "You might as well do \"mkdir <outdir> ; cp -pR * <outdir>\" !"
    exit 1
fi




#begin sanity checking

if [ "$PWD" = "/" ] || [ "$outdir" = "/" ]
then
    echo "ERROR - source and/or destination is the root directory, fool!"
    exit 1
fi

case "$outdir" in
    */ ) outdir=${outdir%/} ;;	# strip outdir of trailing /
esac	

if [ ! $quiet ]; then
    echo "Output directory is $outdir"
fi

if [ ! -d "$outdir" ]
then
    # if [ ! $quiet ]; then echo "making directory $outdir"; fi
    if ! mkdir "$outdir"
    then
        echo "ERROR - Could not create $outdir - exiting.."
        exit 1
    fi
fi

outdirabs=`(cd "$outdir"; pwd -P)`

# check you're not about to overwrite your entire website..
if [ "$PWD" -ef "$outdir" ] || [ "$PWD" = "$outdirabs" ]
then
    echo "ERROR - source and destination are the same directory"
    exit 1
fi	

if [[ "$outdirabs" = "$PWD/"* ]] || [ "$PWD" = "/" ] #first test fails if $PWD="/"
then
    echo "ERROR - destination is a subdirectory of source"
    exit 1
fi	

if [[ "$PWD" = "$outdirabs"* ]]
then
    echo "ERROR - destination is a parent of source directory"
    exit 1
fi	

# end of sanity checking, now do something..


#functions

# make this a function so we can change it later if needed (portability etc)
filesize () {
    echo `find "$1" -printf "%s"`
}




# Main loop starts here

starttime=`date +%s`
files=$(find .)
IFS=$'\n'	# work with files/directories with spaces in them

for file in $files
do
    filepath=${file#*.}	#get path minus leading "."
    
    if [ -d $file ]
    then	
        # echo "$file is a directory"
        ((dircount++))
        if [ -d	$outdir$filepath ]
        then
            #echo "directory $outdir$filepath already exists"
            :
        else
            #echo "mkdir $outdir$filepath"
            mkdir $outdir$filepath
        fi	
    elif [ -h $file ]	# symbolic link
    then
        if [ -f $outdir$filepath ]
        then
            if [ ! $quiet ]; then
                echo "$outdir$filepath already exists"
            fi
            :
        else
            #echo "cp -p $file $outdir$filepath"
            cp -dp $file $outdir$filepath	#don't dereference symbolic links
            if [ ! $quiet ]; then
                echo "$outdir$filepath (symlink)"
            fi
        fi
    elif [ -f $file ]
    then
        # the logic here is ugly, sorry!
        # add more ugly logic here later when doing more overwrite options
        unset doit
        if [ -f $outdir$filepath ]
        then
            # last minute sanity check
            if [ $file -ef $outdir$filepath ]
            then
                echo "ERROR - source and destination are the same file"
                exit 1
            fi	
        
            # if source $file is newer than output file & we're updating..
            if [ $file -nt $outdir$filepath ] && [ $update ]
            then
                doit=1
            elif [ $force ] #overwrite
            then
                doit=1
            fi
        else
            doit=1
        fi
	
	if [ $doit ]
	then
	    ((filecount++))
	    ifilebytes=$(filesize $file)
	    if [ ! $quiet ]; then
            echo -n "$outdir$filepath " # echo "$ifilebytes "
	    fi
	    	    
	    case "$filepath" in
	    	    
		*.[Gg][Ii][Ff] )
		igifbytes=$(($igifbytes+$ifilebytes))
		if [ $giftest = 2 ]
		then
		    if ! gifsicle --colors=256 --no-comments --no-extensions --no-interlace --optimize=2 $file > $outdir$filepath 2> /dev/null
            then
                rm -f $outdir$filepath
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
                cp -p $file $outdir$filepath	#copy anyway?
                # test if the file size did not improve
		    elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]			
		    then
                if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		elif [ $giftest ]
		then
		    if ! giftrans -C $file > $outdir$filepath 2> /dev/null
            then
                rm -f $outdir$filepath
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
                cp -p $file $outdir$filepath	#copy anyway?
                # test if the file size did not improve
		    elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]			
		    then
                if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)		
		ogifbytes=$((ogifbytes+ofilebytes))
		if [ ! $quiet ]; then
		    #echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;

		
		*.[Jj][Pp][Gg] | *.[Jj][Pp][Ee] | *.[Jj][Pp][Ee][Gg] )
		ijpgbytes=$(($ijpgbytes+$ifilebytes))
		if [ $jpgtest ]
		then		    
		    if ! jpegtran -optimize -progressive $file > $outdir$filepath 2> /dev/null
		    then
                rm -f $outdir$filepath
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
                cp -p $file $outdir$filepath

            # test if the file size did not improve over the original with progressive
		    elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then
                # retry non-progressive (sometimes smaller)
                if [ ! $quiet ]; then
                    echo -n "* "
                fi
                jpegtran -optimize $file > $outdir$filepath 2> /dev/null
                if [ $(filesize $outdir$filepath) -ge $ifilebytes ] #file bigger than original
                then #copy it if it still didn't improve
                    if [ ! $quiet ]; then
                        echo -n "! "
                    fi
                    cp -p $file $outdir$filepath
                fi

		    # if in brute mode, try non-progressive anyway
		    elif [ $brute ] #if we get here, the file has been processed OK AND was smaller than the original
		    then
                # retry non-progressive (sometimes smaller)
                jpegtran -optimize $file > $outdir$filepath.wptmp 2> /dev/null  #no failure check as it would have worked the first time
                if [ $(filesize $outdir$filepath.wptmp) -lt $(filesize $outdir$filepath) ] #non progressive is smaller?
                then
                    mv $outdir$filepath.wptmp $outdir$filepath	#replace with non-progressive
                    if [ ! $quiet ]; then
                        echo -n "* "
                    fi
                    #echo -n "brute non-progressive "
                else
                    rm -f $outdir$filepath.wptmp  #otherwise delete temporary non-progressive version
                    #echo -n "brute progressive "
                fi
		    fi
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)
		ojpgbytes=$((ojpgbytes+ofilebytes))
		if [ ! $quiet ]; then
		    # echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;

		
		*.[Pp][Nn][Gg] )
		ipngbytes=$(($ipngbytes+$(filesize $file)))
        if [ $pngtest = 2 ]
		then
            ## optipng creates backup files we don't need if you try to overwrite an existing file, so delete it first
            ## Reported issue #74 to OptiPNG team to resolve, but implement workaround anyway:
            if [ -f $outdir$filepath ]; then rm -f $outdir$filepath; fi
            
            if ! optipng -force $bruteoptipng -out $outdir$filepath $file 2> /dev/null
            then
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
                cp -p $file $outdir$filepath	#copy anyway?
            elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then #copy it if it still didn't improve
		        if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
			fi
        
		elif [ $pngtest ]
		then
		    #pngcrush does stupid things if the output file already exists but the conversion fails, so check first
		    if [ -f $outdir$filepath ]; then rm -f $outdir$filepath; fi
		    if ! pngcrush -q -rem allb $brute $file $outdir$filepath 2> /dev/null || [ ! -f $outdir$filepath ]
                #pngcrush doesn't return an error code if it fails - just deletes output file
                #if [ ! -f $outdir$filepath ]
            then
                #rm -f $outdir$filepath
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
                cp -p $file $outdir$filepath	#copy anyway?
			
                # We STILL need to test if the file got bigger even though
                # pngcrush allegedly copies the original file for us if it
                # grew because in some cases the file gets bigger anyway!?
		    elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]			
		    then
                if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		elif [ $advdeftest ]
		then
		    cp -p $file $outdir$filepath
		    if ! advdef -qz$brute4 $outdir$filepath 2> /dev/null
		    then
                #rm -f $outdir$filepath
                echo -n "$file did not process "                        
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
    			#cp -p $file $outdir$filepath
            elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then #copy it if it still didn't improve
		        if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)
		opngbytes=$((opngbytes+ofilebytes))
		if [ ! $quiet ]; then
		    # echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;


		*.[Hh][Tt][Mm] | *.[Hh][Tt][Mm][Ll] )
		ihtmbytes=$(($ihtmbytes+$(filesize $file)))
		if [ $htmtest = 2 ]
		then	#htmlclean
		    cp -p $file $outdir$filepath
		    if ! htmlclean $outdir$filepath # 2> /dev/null
		    then
                rm -f $outdir$filepath
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
                cp -p $file $outdir$filepath
            elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then #copy it if it still didn't improve
		        if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		    #clean up htmlclean's *.bak files
		    rm -f $outdir$filepath.bak
		elif [ $htmtest ]
		then
		    # htmlcrunch is not used any more, just leaving the code here for the future replacement.
            if ! htmlcr -S $file > $outdir$filepath # 2> /dev/null
		    then
			rm -f $outdir$filepath
			echo -n "$file did not process "
                        
                        ((filecount--))
			((failurecount++))
			#echo "cp -p $file $outdir$filepath"
			cp -p $file $outdir$filepath
                    elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then #copy it if it still didn't improve
		        if [ ! $quiet ]; then
			    echo -n "! "
			fi
			cp -p $file $outdir$filepath
		    fi
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)
		ohtmbytes=$((ohtmbytes+ofilebytes))
		if [ ! $quiet ]; then
		    # echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;


        *.[Zz][Ii][Pp] )
		iothbytes=$(($iothbytes+$(filesize $file)))
		if [ $advziptest ]
		then
		    cp -p $file $outdir$filepath
		    if ! advzip -qz$brute4 $outdir$filepath 2> /dev/null
		    then
                #rm -f $outdir$filepath
                echo -n "$file did not process "
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
    			#cp -p $file $outdir$filepath
            elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then #copy it if it still didn't improve
		        if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)
		oothbytes=$(($oothbytes+$(filesize $outdir$filepath)))
		if [ ! $quiet ]; then
		    # echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;


        *.[Gg][Zz] )
		iothbytes=$(($iothbytes+$(filesize $file)))
		if [ $advdeftest ]
		then
		    cp -p $file $outdir$filepath
		    if ! advdef -qz$brute4 $outdir$filepath 2> /dev/null
		    then
                #rm -f $outdir$filepath
                echo -n "$file did not process "                        
                ((filecount--))
                ((failurecount++))
                #echo "cp -p $file $outdir$filepath"
    			#cp -p $file $outdir$filepath
            elif [ $(filesize $outdir$filepath) -ge $ifilebytes ]
		    then #copy it if it still didn't improve
		        if [ ! $quiet ]; then
                    echo -n "! "
                fi
                cp -p $file $outdir$filepath
		    fi
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)
		oothbytes=$(($oothbytes+$(filesize $outdir$filepath)))
		if [ ! $quiet ]; then
		    # echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;


        *.[Bb][Zz]2 )
		iothbytes=$(($iothbytes+$(filesize $file)))
		if [ $bz2test ]
		then		    
		    ratio=`head -c 4 $file | tail -c 1`
            if [ $ratio != "9" ]
            then
                #echo "ratio is $ratio, recompressing"
                bzip2 -qdc $file | bzip2 -z9 > $outdir$filepath 2> /dev/null
                #this error check is a big kludge - bzip2 doesnt return an error code it seems!
                if [ $(filesize $outdir$filepath) -le 14 ] 
                then
                    rm -f $outdir$filepath
                    echo -n "$file did not process "
                    ((filecount--))
                    ((failurecount++))
                    #echo "cp -p $file $outdir$filepath"
                    cp -p $file $outdir$filepath	#copy anyway?
                fi
            else
                #echo "can't do anything - ratio is 9"
                cp -p $file $outdir$filepath
            fi                    
		else
		    cp -p $file $outdir$filepath	#can't process, just copy
		fi
		ofilebytes=$(filesize $outdir$filepath)
		oothbytes=$(($oothbytes+$(filesize $outdir$filepath)))
		if [ ! $quiet ]; then
		    # echo -n "$ofilebytes "
		    if [ $ifilebytes != "0" ]; then ratio=$((100-100*ofilebytes/ifilebytes)); else ratio=0; fi
		    echo "$((ifilebytes-ofilebytes)) ($ratio%)"
		fi
		;;

		
		*)
		iothbytes=$(($iothbytes+$(filesize $file)))
		if [ ! $quiet ]; then
		    echo #"(copied)"
		fi
		#echo "cp -p $file $outdir$filepath"
		cp -p $file $outdir$filepath
		oothbytes=$(($oothbytes+$(filesize $outdir$filepath)))
		;;
	    esac
	else
	    ((skipcount++))
	    if [ ! $quiet ]; then
            echo "$outdir$filepath (skipped)"
	    fi
	    #echo -n .
	    :
	fi
    else
	if [ ! $quiet ]; then
	    echo "$file is not a file or directory - ignored"
	fi
	#echo "cp -p $file $outdir$filepath"
	#cp -p $file $outdir$filepath	#copy anyway (?)
    fi
done

endtime=`date +%s`
totaltime=$((endtime-starttime))

if [ ! $quiet ]; then
    ibytes=$((ihtmbytes+igifbytes+ijpgbytes+ipngbytes+iothbytes))
    obytes=$((ohtmbytes+ogifbytes+ojpgbytes+opngbytes+oothbytes))
    echo "Directory count: $dircount"
    echo "Processed OK   : $filecount"
    echo "Failures       : $failurecount"
    echo "Skipped Files  : $skipcount"
    if [ $ihtmbytes != "0" ]; then ratio=$((100-100*ohtmbytes/ihtmbytes)); else ratio=0; fi
    echo "Reduction HTML : $((ihtmbytes-ohtmbytes)) ($ratio%)"
    if [ $igifbytes != "0" ]; then ratio=$((100-100*ogifbytes/igifbytes)); else ratio=0; fi
    echo "Reduction GIF  : $((igifbytes-ogifbytes)) ($ratio%)"
    if [ $ijpgbytes != "0" ]; then ratio=$((100-100*ojpgbytes/ijpgbytes)); else ratio=0; fi
    echo "Reduction JPG  : $((ijpgbytes-ojpgbytes)) ($ratio%)"
    if [ $ipngbytes != "0" ]; then ratio=$((100-100*opngbytes/ipngbytes)); else ratio=0; fi
    echo "Reduction PNG  : $((ipngbytes-opngbytes)) ($ratio%)"
    if [ $iothbytes != "0" ]; then ratio=$((100-100*oothbytes/iothbytes)); else ratio=0; fi
    echo "Reduction Other: $((iothbytes-oothbytes)) ($ratio%)"
    echo "Original size  : $ibytes"
    echo "Compressed size: $obytes"
    if [ $ibytes != "0" ]; then ratio=$((100-100*obytes/ibytes)); else ratio=0; fi
    echo "Reduction Total: $((ibytes-obytes)) ($ratio%)"
    echo "Time taken $((totaltime/60)):$((totaltime%60))"
fi

exit 0
