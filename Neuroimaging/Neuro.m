classdef Neuro < handle
   methods (Static)
       
       function CAT12Pipeline(varargin)
            coptions = varargin;
            nii_file = GiveValueForName(coptions,'nii_file');
            if(isempty(nii_file))
                error('Missing mandatory argument nii_file');
            end
            output = GiveValueForName(coptions,'output');
            if(~contains(nii_file,'.gz') && exist(nii_file,'file') < 1)
                nii_file = [nii_file '.gz'];
            end
            [fp,fn,ext] = fileparts(nii_file);
            if(isempty(output))
                output = fullfile(fp,[fn '_CAT12']);
            end
            mkdir(output);
            copyfile(nii_file,fullfile(output,[fn ext]));

            flair_file = GiveValueForName(coptions,'flair_file');
            if(isempty(nii_file))
                use_flair = 0;
            else
                use_flair = 1;
            end            
            
            if(use_flair == 0)
                ExecuteCat12_T1(fullfile(output,[fn ext]),1,0);
            else        
                ExecuteCat12_T1_FLAIR(fullfile(output,[fn ext]),flair_file,1,0);
            end
       end
       
       function CAT12ApplyDeformation(varargin)
            coptions = varargin;
            nii_file = GiveValueForName(coptions,'nii_file');
            if(isempty(nii_file))
                error('Missing mandatory argument nii_file');
            end
            field_file = GiveValueForName(coptions,'field_file');
            if(isempty(field_file))
                error('Missing mandatory argument field_file');
            end
            
            matlabbatch{1}.spm.tools.cat.tools.defs2.field = {field_file};
            matlabbatch{1}.spm.tools.cat.tools.defs2.images = {{nii_file}};
            matlabbatch{1}.spm.tools.cat.tools.defs2.interp = 0;
            matlabbatch{1}.spm.tools.cat.tools.defs2.modulate = 0; 
            
            spm('defaults', 'FMRI');
            spm_jobman('run', matlabbatch);
            
            [fp,fn,ext] = fileparts(nii_file);
            EDTI.FlipPermuteSpatialDimensions('nii_file',fullfile(fp,['w' fn '.nii']),'output',fullfile(fp,['w' fn '_FP.nii']),'flip',[0 1 0])
       end
       
       function SPMBiasFieldCorrection(varargin)
            coptions = varargin;
            nii_file = GiveValueForName(coptions,'nii_file');
            if(isempty(nii_file))
                error('Missing mandatory argument nii_file');
            end
            
            ExecuteBiasFieldCorrection(nii_file);

       end
       
       function MakeAnimatedGIFOfVolume(varargin)
            coptions = varargin;
            gif_file = GiveValueForName(coptions,'gif_file');
            if(isempty(gif_file))
                error('Missing mandatory argument gif_file');
            end
            interactive = GiveValueForName(coptions,'interactive');
            if(isempty(interactive))
                interactive = 1;
            end
            vol_in = GiveValueForName(coptions,'vol');
            if(isempty(vol_in))
                error('Missing mandatory argument vol');
            end 
            overlay_in = GiveValueForName(coptions,'overlay');
            if(isempty(overlay_in))
                overlay_in = [];
            end
            ref_ax = GiveValueForName(coptions,'axes');
            if(isempty(overlay_in))
                ref_ax = 1;
            end           
            
            if(ref_ax == 1)
            elseif(ref_ax == 2)
                vol_in = permute(vol_in,[3 2 1]);
                vol_in = (flip(vol_in,1));
                overlay_in = permute(overlay_in,[3 2 1]);
                overlay_in = (flip(overlay_in,1));               
            elseif(ref_ax == 3)
                vol_in = permute(vol_in,[3 1 2]);
                vol_in = (flip(vol_in,1));
                overlay_in = permute(overlay_in,[3 1 2]);
                overlay_in = (flip(overlay_in,1));               
            end
            
            f=figure;
            filename = gif_file;
            set(gcf,'color','k','inverthardcopy','off')
            if(interactive == 0)
               set(gcf,'visible','off'); 
            end
            ax1=axes;
            ax2=axes;
            for iz=1:size(vol_in,3)
                imagesc(ax1,vol_in(:,:,iz));
                ax1.CLim = [0 max(vol_in(:))];
                colormap(ax1,'gray');
                axis(ax1,'image','off');
                if(~isempty(overlay_in))
                    h=imagesc(ax2,overlay_in(:,:,iz));
                    colormap(ax2,'hot');
                    ax2.CLim = [0 max(overlay_in(:))];
                    set(h,'AlphaData',overlay_in(:,:,iz) ~= 0)
                end
                axis(ax2,'image','off');
                if(interactive == 1)
                    pause(0.1)
                end
                frame = getframe(f); 
                im = frame2im(frame); 
                [imind,cm] = rgb2ind(im,256); 
                % Write to the GIF File 
                if iz == 1 
                  imwrite(imind,cm,filename,'gif', 'Loopcount',inf,'DelayTime',0.1); 
                else 
                  imwrite(imind,cm,filename,'gif','WriteMode','append','DelayTime',0.1); 
                end 

            end

            close(f)
 
       end
   end
end


% Helper: finds a parameter by name when using varargin
function value = GiveValueForName(coptions,name)
value = [];
for ij=1:2:length(coptions)
    if(strcmpi(coptions{ij},name))
        value = coptions{ij+1};
        return
    end
end
end

function ExecuteCat12_T1(tgt_file,ncores,showreport)
global MRIToolkit;
spm_path = MRIToolkit.spm_path;

if(isempty(which('spm')))
    addpath(genpath(spm_path));
end

if(nargin < 2 || showreport > 0)
    showreport = 2;
end

% if(ispc)
if(true)
matlabbatch{1}.spm.tools.cat.estwrite.data = {tgt_file};
matlabbatch{1}.spm.tools.cat.estwrite.nproc = 0;
matlabbatch{1}.spm.tools.cat.estwrite.opts.tpm = {fullfile(spm_path,'tpm','TPM.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.opts.affreg = 'mni';
matlabbatch{1}.spm.tools.cat.estwrite.opts.biasstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.opts.samp = 3;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.APP = 1070;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.NCstr = -Inf;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.LASstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.gcutstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.cleanupstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.WMHCstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.WMHC = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.restypes.best = [0.5 0.3];
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.darteltpm = {fullfile(spm_path,'toolbox','cat12','templates_1.50mm','Template_1_IXI555_MNI152.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.shootingtpm = {fullfile(spm_path,'toolbox','cat12','templates_1.50mm','Template_0_IXI555_MNI152_GS.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.regstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.vox = 1.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.pbtres = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.scale_cortex = 0.7;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.add_parahipp = 0.1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.close_parahipp = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.ignoreErrors = 1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.verb = 2;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.print = 2;
matlabbatch{1}.spm.tools.cat.estwrite.output.surface = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.neuromorphometrics = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.lpba40 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.cobra = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.hammers = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ibsr = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.aal = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.mori = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.anatomy = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.jacobian.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.warps = [1 1];  

else
    
matlabbatch{1}.spm.tools.cat.estwrite.data = {tgt_file};
matlabbatch{1}.spm.tools.cat.estwrite.nproc = 0;
matlabbatch{1}.spm.tools.cat.estwrite.opts.tpm = {fullfile(spm_path,'/tpm/TPM.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.opts.affreg = 'mni';
matlabbatch{1}.spm.tools.cat.estwrite.opts.biasstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.opts.samp = 3;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.APP = 1070;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.NCstr = -Inf;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.LASstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.gcutstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.cleanupstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.WMHCstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.WMHC = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.restypes.best = [0.5 0.3];
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.darteltpm = {fullfile(spm_path,'/toolbox/cat12/templates_1.50mm/Template_1_IXI555_MNI152.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.shootingtpm = {fullfile(spm_path,'/toolbox/cat12/templates_1.50mm/Template_0_IXI555_MNI152_GS.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.regstr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.vox = 1.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.pbtres = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.scale_cortex = 0.7;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.add_parahipp = 0.1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.close_parahipp = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.ignoreErrors = 1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.verb = 1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.print = 0;%showreport;
matlabbatch{1}.spm.tools.cat.estwrite.output.surface = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.neuromorphometrics = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.lpba40 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.cobra = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.hammers = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ibsr = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.aal = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.mori = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.anatomy = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.jacobian.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.warps = [0 0];
end

spm('defaults', 'FMRI');
spm_jobman('run', matlabbatch);

end

function ExecuteCat12_T1_FLAIR(t1_file,flair_file,ncores,showreport)
global MRIToolkit;
spm_path = MRIToolkit.spm_path;

if(isempty(which('spm')))
    addpath(genpath(spm_path));
end

if(nargin < 2 || showreport > 0)
    showreport = 2;
end

matlabbatch{1}.spm.tools.cat.estwrite.data = {t1_file};
matlabbatch{1}.spm.tools.cat.estwrite.data_wmh = {flair_file};
matlabbatch{1}.spm.tools.cat.estwrite.nproc = 0;
matlabbatch{1}.spm.tools.cat.estwrite.opts.tpm = {fullfile(spm_path,'tpm','TPM.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.opts.affreg = 'mni';
matlabbatch{1}.spm.tools.cat.estwrite.opts.bias.biasstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.opts.ngaus = [1 1 2 3 4 2];
matlabbatch{1}.spm.tools.cat.estwrite.opts.warpreg = [0 0.001 0.5 0.05 0.2];
matlabbatch{1}.spm.tools.cat.estwrite.opts.samp = 3;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.APP = 1070;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.NCstr = -Inf;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.LASstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.gcutstr = 2;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.cleanupstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.BVCstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.WMHCstr = 2.22044604925031e-16;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.WMHC = 3;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.mrf = 1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.segmentation.restypes.fixed = [1 0.1];
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.T1 = {fullfile(spm_path,'toolbox','FieldMap','T1.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.brainmask = {fullfile(spm_path,'toolbox','FieldMap','brainmask.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.cat12atlas = {fullfile(spm_path,'toolbox','cat12','templates_1.50mm','cat.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.darteltpm = {fullfile(spm_path,'toolbox','cat12','templates_1.50mm','Template_1_IXI555_MNI152.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.shootingtpm = {fullfile(spm_path,'toolbox','cat12','templates_1.50mm','Template_0_IXI555_MNI152_GS.nii')};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.regstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.vox = 1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.pbtres = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.scale_cortex = 0.7;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.add_parahipp = 0.1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.surface.close_parahipp = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.experimental = 1;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.lazy = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.ignoreErrors = 0;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.verb = 2;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.admin.print = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.surface = 12;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.neuromorphometrics = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.lpba40 = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.cobra = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.hammers = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ibsr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.aal = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.mori = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.anatomy = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ct.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ct.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ct.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WMH.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.TPMC.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.TPMC.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.TPMC.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.TPMC.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlas.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.native = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.native = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.las.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.jacobian.warped = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.warps = [1 1];

spm('defaults', 'FMRI');
spm_jobman('run', matlabbatch);

end

function ExecuteBiasFieldCorrection(input_file)
    global MRIToolkit;
    spm_path = MRIToolkit.spm_path;
    
    matlabbatch{1}.spm.spatial.preproc.channel.vols = {[input_file ',1']};
    matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
    matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 60;
    matlabbatch{1}.spm.spatial.preproc.channel.write = [1 1];
    matlabbatch{1}.spm.spatial.preproc.tissue(1).tpm = {fullfile(spm_path,'/tpm/TPM.nii,1')};
    matlabbatch{1}.spm.spatial.preproc.tissue(1).ngaus = 1;
    matlabbatch{1}.spm.spatial.preproc.tissue(1).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(1).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(2).tpm = {fullfile(spm_path,'/tpm/TPM.nii,2')};
    matlabbatch{1}.spm.spatial.preproc.tissue(2).ngaus = 1;
    matlabbatch{1}.spm.spatial.preproc.tissue(2).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(2).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(3).tpm = {fullfile(spm_path,'/tpm/TPM.nii,3')};
    matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;
    matlabbatch{1}.spm.spatial.preproc.tissue(3).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(3).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(4).tpm = {fullfile(spm_path,'/tpm/TPM.nii,4')};
    matlabbatch{1}.spm.spatial.preproc.tissue(4).ngaus = 3;
    matlabbatch{1}.spm.spatial.preproc.tissue(4).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(4).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(5).tpm = {fullfile(spm_path,'/tpm/TPM.nii,5')};
    matlabbatch{1}.spm.spatial.preproc.tissue(5).ngaus = 4;
    matlabbatch{1}.spm.spatial.preproc.tissue(5).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(5).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(6).tpm = {fullfile(spm_path,'/tpm/TPM.nii,6')};
    matlabbatch{1}.spm.spatial.preproc.tissue(6).ngaus = 2;
    matlabbatch{1}.spm.spatial.preproc.tissue(6).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(6).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
    matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
    matlabbatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
    matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
    matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
    matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
    matlabbatch{1}.spm.spatial.preproc.warp.write = [0 0];
    
    spm('defaults', 'FMRI');
    spm_jobman('run', matlabbatch);
end
