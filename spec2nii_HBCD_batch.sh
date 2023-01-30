#!/bin/bash
ZipLoc=$1
OutputDIR=$2
# Function for HBCD spec2nii BIDS conversion on raw data. This function will take an appropriately named zip file:
#	1) Extract the file to the current work directory
# 2) Identify format from files
#	2) Loop over the files running spec2nii
#	3) Use NIfTI header info to identify the acquisitions
#	4) Check dimensions of the HERCULES data and separate HYPER water
#	5) Create BIDS-compliant file names and copy data to the target directory
#
# Inputs:
#	ZipLoc = Path to data zip file
#	OutputDIR = Path to send the data after conversion. Directory will be created and exisiting content will be overwritten
#
#
# Developed on Python 3.9.15 macOS Montery 12.5
#
# DEPENDENCIES:
# Python packages
# spec2nii v0.6.1 (https://github.com/wtclarke/spec2nii)
# fsl-mrs v1.1.2 (https://open.win.ox.ac.uk/pages/fsl/fsl_mrs/install.html)
#
# other packages
# Non unix OS users need to install the following package to expand tar and zip archives:
# unar v1.10.7 (https://theunarchiver.com/command-line)/(https://formulae.brew.sh/formula/unar)
#
# For the data/list and txt based dcm dump you have to install the DCMTK tool to convert txt to dcm:
# dcmtk v3.6.7 (https://dicom.offis.de/dcmtk.php.en)
#
# NOTE:
# Tested formats: sdat (HYPER), twix (XA30/VE11), data/list/dcmtxtdump
#
# TODO: Test for GE p-files, flag to use backup format
#
# first version C.W.Davies-Jenkins, Johns Hopkins 2023
# modifed by Helge Zollner, Johns Hopkins 01-21-23

# Create output directory
mkdir -p $OutputDIR

# Directory for temporary files:
Staging=$PWD
Staging="$Staging"/temp/

# Extract info from zip file name
ZipName=$(basename -- "$ZipLoc")
extension="${ZipName##*.}"
ZipName="${ZipName%.*}"
IFS=$'_'
ZipSplit=($ZipName)
unset IFS;

# Definitions according to the zip file naming conventions:
PSCID=${ZipSplit[0]}
DCCID=${ZipSplit[1]}
VisitID=${ZipSplit[2]}

# Unarchive the file (works for zip and tar):
unar $ZipLoc -o $Staging -f

# Save path to top level directory
TopLevelDIR=$Staging

# Initilize with no format
Format="none"
# Loop over files in temporary directroy
for f in $(find "$TopLevelDIR" -type f -name "*");
do
  # Generate path, filename, and extensions
  path=${f%/*}
  file=${f##*/}
  extension=${f##*.}
  # Identification begins here
  # Philips SDAT/SPAR
  if [[ $extension == "SDAT" ]] || [[ $extension == "sdat" ]]; then
     Format="sdat"
  fi
  # Siemens TWIX
  if [[ $extension == "dat" ]]; then
     Format="twix"
  fi
  # GE p-files
  if [[ $extension == "7" ]]; then
     Format="ge"
  fi
  # Philips data/list/dcmtxtdump following Sandeeps description
  if [[ $extension == "zip" ]]; then
    # Find zip archive with .data/.list pair ignore DICOM zip
     if ! [[ $file == "Classic_DICOM.zip" ]]; then
       Format="data"
       unar $f -o $path -f -D
       # Move .data/.list pair in temporary directory
        for dl in $(find "$path" -type f -name "*.list");
        do
          mv -f "$dl" "$TopLevelDIR"/HYPER.list
        done;
        for dl in $(find "$path" -type f -name "*.data");
        do
          mv -f "$dl" "$TopLevelDIR"/HYPER.data
        done;
        # Find dcmtxtdump and convert to DICOM
        for tx in $(find "$path" -type f -name "*.txt");
        do
          mv -f "$tx" "$TopLevelDIR"/dcmdump.txt
        done;
        txt="$TopLevelDIR"/dcmdump.txt
        dcm="$TopLevelDIR"/dcmdump.dcm
        if ! [[ -f "$txt" ]]; then
            Format="none"
            echo No dcmdump txt file found
        else
            eval "dump2dcm $txt $dcm"
        fi
     fi
  fi
done;

echo Data format: $Format
echo Location of zip file: $ZipLoc
echo Location of output directory: $OutputDIR
echo Temp dir: $Staging
echo PSCID: $PSCID
echo DCCID: $DCCID
echo VisitID: $VisitID

# Unable to parse format from files ... skip to end
if [ $Format == "none" ]; then
  echo Unable to identify file format. Check folder structure.
  exit 0
fi

# Based on format, setup spec2nii source and file extensions
case $Format in
    twix)
        CMD="spec2nii twix -e image "
        Ext=".dat"
        ;;
    sdat)
        CMD="spec2nii philips "
        Ext=".sdat"
        # Rename to all caps extensions
        for f in $(find "$TopLevelDIR" -type f -name "*$Ext");
        do
          mv "$f" "${f//sdat/SDAT}";
        done
        for f in $(find "$TopLevelDIR" -type f -name "*spar");
        do
          mv "$f" "${f//spar/SPAR}";
        done
        Ext=".SDAT"
        ;;
    data)
        CMD="spec2nii philips_dl "
        Ext=".data"
        ;;
    ge)
        CMD="spec2nii ge "
        Ext=".7"
        ;;
    dicom)
        CMD="spec2nii dicom "
        Ext=".dcm"
        ;;
esac

# Loop over files found with the specified extension and perform conversion:
for f in $(find "$TopLevelDIR" -type f -name "*$Ext");
do
  file=${f##*/}
  ini=${file:0:1}
  if ! [[ $ini == "." ]] ; then
      if [ $Format == "sdat" ] ;then
  	    # Need to handle spar.
        FilePath="${f%$Ext}.SPAR"
        FilePath="$f $FilePath"
      elif [ $Format == "data" ] ;then
        FilePath="${f%$Ext}.list"
        FilePath="$f $FilePath $dcm"
      else
        #statements
        FilePath="$f"
      fi

      # Run spec2nii initial call:
      eval "$CMD $FilePath -o $TopLevelDIR"

      # Some cleanup:
      if [ $Format == "sdat" ];then
        rm "${f%$Ext}.SPAR"
      fi
      rm "$f"
    fi
done;

# Separate loop for json dump and anonomize
# Initialize number of files:
no_files=1
for f in $(find "$TopLevelDIR" -type f -name "*.nii.gz");
do
  file=${f##*/}
  ini=${file:0:1}
  if ! [[ $ini == "." ]] ; then
    # Get header dump from NIfTI file and convert to array:
    Dump=$(eval "spec2nii dump $f")
    IFS=$'\n'
    array=($Dump)
    unset IFS;

    # Initialize relevant dimension variables:
    Coil=0
    Dyn=0
    Edit=0

    # Loop over array to grab for individual fields
    for i in "${array[@]}"
    do
        if [[ $i == *"EchoTime"* ]]; then
	    TE=${i#*:}
	    TE=${TE::5}
	elif [[ $i == *"dim             :"* ]]; then
	    Dim=${i#*: [}
	    Dim=${Dim%?}
  	    Dim=($Dim)
	elif [[ $i == *"ProtocolName"* ]]; then
	    Prot=${i#*:}
	    Prot=${Prot%?}
	elif [[ $i == *"TxOffset"* ]]; then
	    Offset=${i#*:}
	    Offset=${Offset%?}
	    if [[ $Offset == *"-1."* ]]; then
	        Suff="svs"
	    elif [[ $Offset == *"0.0"* ]]; then
	        Suff="ref"
            fi
	elif [[ $i == *"dim_"* ]]; then
	    # If coil dimension, then see which dimension it specifies:
	    if [[ $i == *"COIL"* ]]; then
		Coil=${i:6:1}
	    elif [[ $i == *"DYN"* ]]; then
		Dyn=${i:6:1}
	    elif [[ $i == *"EDIT"* ]]; then
		Edit=${i:6:1}
	    fi
        fi
    done

    # Use prot or filename to decide on acq;
    # Get suffix for hyper sequences
    if [[ $f == *"HYPER"* ]]; then
      if [[ $f == *"short_te"* ]]; then
      	Acq="shortTE"
      elif [[ $f == *"edited"* ]]; then
      	Acq="hercules"
      fi
      if [[ $f == *"act"* ]]; then
      	Suff="svs"
      elif [[ $f == *"ref"* ]]; then
      	Suff="ref"
      fi
      if [ $Format == "data" ] ;then
        if [[ $f == *"edited"* ]] ||[[ $f == *"short_te"* ]]; then
        	Suff="svs"
        elif [[ $f == *"ref"* ]]; then
        	Suff="ref"
        fi
      fi
    else
      if [[ $Prot == *"PRESS"* ]]; then
      	Acq="shortTE"
          elif [[ $Prot == *"HERC"* ]]; then
      	Acq="hercules"
      fi
    fi

    if [[ $f == *"HYPER"* ]]; then
      if [ $Format == "data" ] ;then
        if [[ $f == *"ref"* ]]; then
          eval "mrs_tools split --file $f --dim DIM_USER_0 --indices 0 1 2 3 --output $TopLevelDIR"
        fi
      fi
    fi

    if (( $no_files > 4 )); then
      AddSuff=$((no_files-4))
      echo Add Suffix $AddSuff
      Suff="$Suff"-"$AddSuff"
      echo New Suff: $Suff
    fi

    # NAMING CONVENTION FOR OUTPUT DATA
    BIDS_NAME=/sub-"$PSCID""$DCCID"_ses-"$VisitID"_acq-"$Acq"_"$Suff".nii.gz
    OutFile="$OutputDIR"/"$BIDS_NAME"

    if ! [[ $f == *"NOI"* ]]; then
      if ! [[ $f == *"water"* ]]; then
        # Move NIfTI to output folder
        mv -f "$f" "$OutFile"
        # Extract JSON sidecar and anonomize the NIfTI data:
        eval "spec2nii anon $OutFile -o $OutputDIR"
        eval "spec2nii extract $OutFile"
        JSON_BIDS_NAME=/sub-"$PSCID""$DCCID"_ses-"$VisitID"_acq-"$Acq"_"$Suff".json
        JsonOutFile="$OutputDIR"/"$JSON_BIDS_NAME"
        nTE=0
        if [[ $Acq == *"shortTE"* ]] && ! [[ $TE == *"0.035"* ]]; then
          nTE=0.035
        fi
        if [[ $Acq == *"shortTE"* ]] && ! [[ $TE == *"0.035"* ]]; then
          nTE=0.035
        fi
        if [[ $Acq == *"hercules"* ]] && ! [[ $TE == *"0.08"* ]]; then
          nTE=0.08
        fi
        if ! [[ $nTE == 0 ]]; then
PYCMD=$(cat <<EOF
import json
jsonHeaderFile = open("$JsonOutFile")
HeaderFileData = json.load(jsonHeaderFile)
jsonHeaderFile.close()
newEchoTime = {"EchoTime": $nTE}
HeaderFileData.update(newEchoTime)
file = open("$JsonOutFile", 'w+')
json.dump(HeaderFileData, file, indent=4)
file.close()
EOF
)
python -c "$PYCMD"

          # Overwrite orignial json header extension
          eval "spec2nii insert $OutFile $JsonOutFile -o $OutputDIR"
        fi

      else
        Acq="hercules"
        BIDS_NAME=/sub-"$PSCID""$DCCID"_ses-"$VisitID"_acq-"$Acq"_"$Suff".nii.gz
        OutFile="$OutputDIR"/"$BIDS_NAME"
        sp="$TopLevelDIR"/HYPER_hyper_water_ref_selected.nii.gz
        # Move NIfTI to output folder
        mv -f "$sp" "$OutFile"
        # Extract JSON sidecar and anonomize the NIfTI data:
        eval "spec2nii anon $OutFile -o $OutputDIR"
        eval "spec2nii extract $OutFile"
        JSON_BIDS_NAME=/sub-"$PSCID""$DCCID"_ses-"$VisitID"_acq-"$Acq"_"$Suff".json
        JsonOutFile="$OutputDIR"/"$JSON_BIDS_NAME"
        nTE=0
        if [[ $Acq == *"shortTE"* ]] && ! [[ $TE == *"0.035"* ]]; then
          nTE=0.035
        fi
        if [[ $Acq == *"hercules"* ]] && ! [[ $TE == *"0.08"* ]]; then
          nTE=0.08
        fi
        if ! [[ $nTE == 0 ]]; then
PYCMD=$(cat <<EOF
import json
jsonHeaderFile = open("$JsonOutFile")
HeaderFileData = json.load(jsonHeaderFile)
jsonHeaderFile.close()
newHeader = {"EchoTime": $nTE, "dim_6": "DIM_DYN"}
HeaderFileData.update(newHeader)
file = open("$JsonOutFile", 'w+')
json.dump(HeaderFileData, file, indent=4)
file.close()
EOF
)
python -c "$PYCMD"

          # Overwrite orignial json header extension
          eval "spec2nii insert $OutFile $JsonOutFile -o $OutputDIR"
        fi

        Acq="shortTE"
        BIDS_NAME=/sub-"$PSCID""$DCCID"_ses-"$VisitID"_acq-"$Acq"_"$Suff".nii.gz
        OutFile="$OutputDIR"/"$BIDS_NAME"
        sp="$TopLevelDIR"/HYPER_hyper_water_ref_others.nii.gz
        # Move NIfTI to output folder
        mv -f "$sp" "$OutFile"
        # Extract JSON sidecar and anonomize the NIfTI data:
        eval "spec2nii anon $OutFile -o $OutputDIR"
        eval "spec2nii extract $OutFile"
        JSON_BIDS_NAME=/sub-"$PSCID""$DCCID"_ses-"$VisitID"_acq-"$Acq"_"$Suff".json
        JsonOutFile="$OutputDIR"/"$JSON_BIDS_NAME"
        nTE=0
        if [[ $Acq == *"shortTE"* ]] && ! [[ $TE == *"0.035"* ]]; then
          nTE=0.035
        fi
        if [[ $Acq == *"hercules"* ]] && ! [[ $TE == *"0.08"* ]]; then
          nTE=0.08
        fi
        if ! [[ $nTE == 0 ]]; then
PYCMD=$(cat <<EOF
import json
jsonHeaderFile = open("$JsonOutFile")
HeaderFileData = json.load(jsonHeaderFile)
jsonHeaderFile.close()
newHeader = {"EchoTime": $nTE, "dim_6": "DIM_DYN"}
HeaderFileData.update(newHeader)
file = open("$JsonOutFile", 'w+')
json.dump(HeaderFileData, file, indent=4)
file.close()
EOF
)
python -c "$PYCMD"

          # Overwrite orignial json header extension
          eval "spec2nii insert $OutFile $JsonOutFile -o $OutputDIR"
        fi
      fi
    fi
    no_files=$((no_files+1))
  fi
done;
no_files=$((no_files-1))

# Some cleanup:
rm -r -f "$Staging"

# Final message
if (( $no_files == 4 ));then
  echo Success! 4 nii files generated.
fi
if (( $no_files < 4 ));then
  echo Warning! $no_files nii files generated. Check MRS archive.
fi
if (( $no_files > 4 ));then
  echo Warning! $no_files nii files generated but we expect only 4. Ensure correct job setup.
fi
