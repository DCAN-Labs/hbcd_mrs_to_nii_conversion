import os, glob, json
import nibabel as nib
import numpy as np
import argparse

def build_parser():

    #Configure the commands that can be fed to the command line
    parser = argparse.ArgumentParser()
    parser.add_argument("mrs_dir", help="The <output_dir>/sub-<label>/ses-<label>/mrs folder where nifti files live", type=str)
    return parser

def main():

    parser = build_parser()
    args = parser.parse_args()

    mrs_niftis = glob.glob(os.path.join(args.mrs_dir, "*.nii.gz"))
    for temp_nifti in mrs_niftis:
        temp_img = nib.load(temp_nifti)
        spectral_width = 1/temp_img.header['pixdim'][4]
        json_file = temp_nifti.replace(".nii.gz", ".json")
        with open(json_file, 'r') as f:
            json_data = json.load(f)
        if "ReceiveCoilName" in json_data.keys():
            if type(json_data["ReceiveCoilName"]) is dict:
                if "Value" in json_data["ReceiveCoilName"].keys():
                    json_data["ReceiveCoilName"] = json_data["ReceiveCoilName"]["Value"]
                    print("Updated ReceiveCoilName to string in {}".format(json_file))
        if 'SpectralWidth' in json_data:
            print('SpectralWidth already exists in {}, skipping'.format(json_file))
        else:
            json_data['SpectralWidth'] = spectral_width
        with open(json_file, 'w') as f:
            json.dump(json_data, f, indent=4)
        print('Added SpectralWidth value of {} to {} (taken from fifth entry of pixdim field)'.format(spectral_width, json_file))


if __name__ == "__main__":
    main()