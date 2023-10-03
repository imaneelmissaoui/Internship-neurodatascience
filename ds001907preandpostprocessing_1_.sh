
# Openneuro post+preprocessing
ConvertSubject(){
    subject=$1
    session=$2
    fileNiiGZ="sub-${subject}_ses-${session}_dwi.nii.gz"  
    fileBvec="sub-${subject}_ses-${session}_dwi.bvec"  
    fileBval="sub-${subject}_ses-${session}_dwi.bval" 
    
    # nii, bvec, bval  
    #Preprocessing
    # Convert NIFTI to .mif and include gradient information
    mrconvert  $fileNiiGZ "dwi.mif" -fslgrad $fileBvec $fileBval
    
    # Denoising
    dwidenoise dwi.mif dwi_den.mif -noise noise.mif

    # Calculate residual
    mrcalc dwi.mif dwi_den.mif -subtract residual.mif

    
    dwifslpreproc dwi_den.mif dwi_den_preproc.mif -rpe_none -nocleanup -pe_dir AP -eddy_options " --slm=linear"


    # Bias correction
    dwibiascorrect ants dwi_den_preproc.mif dwi_den_preproc_unbiased.mif -bias bias.mif

    #Post processing
    # Generate mask
    dwi2mask dwi_den_preproc_unbiased.mif mask.mif

    # Estimating the basis function using Tournier algorithm
    dwi2response tournier dwi_den_preproc_unbiased.mif response.txt -voxels voxels.mif
    # Viewing the basis functions
    # mrview dwi.mif -overlay.load voxels.mif
    # shview response.txt
    
    
    # Applying the basis functions to the diffusion data
    dwi2fod csd dwi_den_preproc_unbiased.mif -mask mask.mif response.txt fod.mif

    # Viewing the FODs
    # mrview fod.mif

    # Normalizing the FODs
    mtnormalise fod.mif fod_norm.mif -mask mask.mif

    # Convert the anatomical image to MRtrix format
    mrconvert ${ANAT_PATH}/sub-${subject}_ses-${session}_T1wbrain.nii.gz T1.mif  

    # Segment the anatomical image with FSL's FAST
    5ttgen fsl T1.mif 5tt_nocoreg.mif

    # Extract the b0 images
    dwiextract dwi.mif - -bzero | mrmath - mean mean_b0.mif -axis 3

    # Convert the b0 and 5tt images
    mrconvert mean_b0.mif mean_b0.nii.gz
    mrconvert 5tt_nocoreg.mif 5tt_nocoreg.nii.gz

    # Extract the grey matter segmentation
    fslroi 5tt_nocoreg.nii.gz 5tt_vol0.nii.gz 0 1

    # Coregister the anatomical and diffusion datasets
    flirt -in mean_b0.nii.gz -ref 5tt_vol0.nii.gz -interp nearestneighbour -dof 6 -omat diff2struct_fsl.mat

    # Convert the transformation matrix to MRtrix format
    transformconvert diff2struct_fsl.mat mean_b0.nii.gz 5tt_nocoreg.nii.gz flirt_import diff2struct_mrtrix.txt

    # Apply the transformation matrix to the non-coregistered segmentation data
    mrtransform 5tt_nocoreg.mif -linear diff2struct_mrtrix.txt -inverse 5tt_coreg.mif

    # View the coregistration in mrview
    # mrview dwi.mif -overlay.load 5tt_nocoreg.mif -overlay.colourmap 2 -overlay.load 5tt_coreg.mif -overlay.colourmap 1

    # Create the grey matter / white matter boundary
    5tt2gmwmi 5tt_coreg.mif gmwmSeed_coreg.mif

    # View the GM/WM boundary
    # mrview dwi.mif -overlay.load gmwmSeed_coreg.mif

    # Create streamlines with tckgen
    tckgen -act 5tt_coreg.mif -backtrack -seed_gmwmi gmwmSeed_coreg.mif -nthreads 16 -maxlength 250 -cutoff 0.06 -select 40000000 fod_norm.mif tracks_40M.tck

    # Extract a subset of tracks
    tckedit tracks_40M.tck -number 200k smallerTracks_200k.tck

    # View the tracks in mrview
    # mrview dwi.mif -tractography.load smallerTracks_200k.tck

    # Sift the tracks with tcksift2
    tcksift2 -act 5tt_coreg.mif -out_mu sift_mu.txt -out_coeffs sift_coeffs.txt -nthreads 16 tracks_40M.tck fod_norm.mif sift_1M.txt

    #Running recon-all
    export SUBJECTS_DIR=$(pwd)
    recon-all -i ${ANAT_PATH}/sub-${subject}_ses-${session}_T1wbrain.nii.gz -s recon -all

    #Converting the labels
    fsLocation="/home/imane/mambaforge/envs/myenv/share/mrtrix3/labelconvert/fs_a2009s.txt"
    labelconvert recon/mri/aparc.a2009s+aseg.mgz $FREESURFER_HOME/FreeSurferColorLUT.txt $fsLocation parcels.mif

    #Coregistering the parcellation:
    mrtransform parcels.mif -interp nearest -linear diff2struct_mrtrix.txt -inverse -datatype uint32 parcels_coreg.mif

    #Creating the connectome WITH coregistration
    tck2connectome -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in sift_1M.txt tracks_40M.tck parcels_coreg.mif parcels_coreg.csv -out_assignment assignments_parcels_coreg.csv



}

# ---------------------- END OF FUNCTION DEFINITION -------------------------------------


subjects=("RC4115" "RC4110" "RC4111" "RC4112" "RC4113" "RC4114" )
sessions=("1")

# Add your free surfer install to home.
DATASET_PATH="/media/imane/DATA/openneuro/ds001907"
#set freesurfer home
export FREESURFER_HOME=/home/imane/freesurfer/usr/local/freesurfer/7.4.1
source $FREESURFER_HOME/SetUpFreeSurfer.sh
#set ants path
export ANTSPATH=/opt/ANTs/bin/
export PATH=${ANTSPATH}:$PATH




for subject in "${subjects[@]}"
do
    for session in "${sessions[@]}"
    do
         # Define paths
        DWI_PATH="${DATASET_PATH}/sub-${subject}/ses-${session}/dwi"
        ANAT_PATH="${DATASET_PATH}/derivatives/sub-${subject}/ses-${session}/anat"
    
         # Navigate to the DWI directory
        cd ${DWI_PATH}
     
        
        echo "Currently working on Subject $subject, session $session"
        ConvertSubject $subject $session
        printf "\n"

        
       
    done 
done
