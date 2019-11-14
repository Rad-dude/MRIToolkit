%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%%%% Alberto De Luca - alberto@isi.uu.nl $%%%%%% Distributed under the terms of LGPLv3  %%%
%%% Distributed under the terms of LGPLv3  %%%
% Spherical deconvolution class - including GRL and mFOD
% A. De Luca - UMC Utrecht - 28/10/2019 - alberto@isi.uu.nl -
% alberto.deluca.06@gmail.com
% First version: 28/10/2019

classdef SphericalDeconvolution < handle
    properties
        data;
        n_isotropic;
        n_anisotropic;
        deconv_method;
        inner_shells_weight;
        rf_indices_lr;
        rf_indices_hr;
        rf_models;
        L2LSQ_reg;
        LRKernel;
        HRKernel;
        nDirections;
        NN_L, NN_H;
    end
    
    methods
        
        % Class constructor. Accepts only 1 optional argument:
        % data, a structure with fields "img" (the 4D data matrix), "bvals"
        % the b-values, "bvecs" the gradient vectors
        function obj = SphericalDeconvolution(varargin)
            obj.data = [];
            obj.n_anisotropic = 0;
            obj.n_isotropic = 0;
            obj.deconv_method = [];
            obj.inner_shells_weight = 0.2;
            obj.rf_indices_lr = {};
            obj.rf_indices_hr = {};
            obj.LRKernel = [];
            obj.HRKernel = [];
            obj.L2LSQ_reg = 0.1;
            obj.nDirections = 300;
            obj.NN_L = 0;
            obj.NN_H = 0;
            obj.rf_models = {};
            
            InputPairs = ParseInputKeys(varargin);
            for ij=1:size(InputPairs,1)
                if(strcmpi(InputPairs{ij,1},'data'))
                    obj.data = InputPairs{ij,2};
                end
            end
        end
        
%       % How the inner shells are weighted in the deconvolution (0-1)
        function setInnerShellWeighting(obj,weight)
            obj.inner_shells_weight = weight;
        end
        
        % Returns true if everything is set properly and ready to go
        function boolean = isInitialized(obj)
            boolean = (obj.n_anisotropic + obj.n_isotropic ~= 0) & ...
                SphericalDeconvolution.isSupportedMethod(obj.deconv_method) & ~isempty(obj.data) & ...
                ~isempty(obj.LRKernel) & ~isempty(obj.HRKernel) & obj.nDirections > 0;
            if(strcmpi(obj.deconv_method,'dRL'))
                boolean = boolean & obj.NN_L ~= 0 & obj.NN_H ~= 0;
            end
        end
        
        % Add an isotropic response function (i.e. CSF) to the
        % deconvolution matrix. These should be add only after all
        % anisotropic RFs have been added.
        function obj = AddIsotropicRF(obj,D)
            if(isempty(obj.data))
                warning('Cannot initialize RFs if data has not been set. Bailing out.');
                return
            end
            obj.n_isotropic = obj.n_isotropic+1;
            IndexHR = size(obj.HRKernel,2)+1;
            IndexLR = size(obj.LRKernel,2)+1;
            [~,lLRKernel,lHRKernel] = mDRLMT_MakeDKIKernel_multicomp(obj.data,10,[1.7e-3 0.5e-3 0.5e-3],0,D,1);
            if(~isempty(obj.LRKernel))
                obj.LRKernel(:,IndexLR) = lLRKernel(:,end);
                obj.HRKernel(:,IndexHR) = lHRKernel(:,end);
            else
                obj.LRKernel = lLRKernel(:,end);
                obj.HRKernel = lHRKernel(:,end);
            end
            obj.rf_indices_lr(end+1) = {IndexLR};
            obj.rf_indices_hr(end+1) = {IndexHR};
            obj.rf_models(end+1) = {'ADC'};
        end
        
        % Add an anisotropic RF based on the DTI/DKI model. These can be
        % added only before any isotropic RF. Eigenvalues is a vector
        % containing the three main eigenvalues of the diffusion tensor,
        % whereas meankurtosis is a scalar.
        function obj = AddAnisotropicRF_DKI(obj,EigenValues,MeanKurtosis)
            if(isempty(obj.data))
                warning('Cannot initialize RFs if data has not been set. Bailing out.');
                return
            end
            if(obj.n_isotropic ~= 0)
                warning('Please add all anisotropic RFs before any isotropic component.');
                return
            end
            pass_data = obj.data;
            pass_data.bvecs(:,3) = -pass_data.bvecs(:,3);
            obj.n_anisotropic = obj.n_anisotropic+1;
            [~,lLRKernel,lHRKernel] = mDRLMT_MakeDKIKernel_multicomp(pass_data,obj.nDirections,EigenValues,MeanKurtosis,[],1);
            IndexHR = size(obj.HRKernel,2)+1:size(obj.HRKernel,2)+obj.nDirections;
            IndexLR = size(obj.LRKernel,2)+1:size(obj.LRKernel,2)+size(lLRKernel,2);
            if(~isempty(obj.LRKernel))
                obj.LRKernel(:,IndexLR) = lLRKernel;
                obj.HRKernel(:,IndexHR) = lHRKernel;
            else
                obj.LRKernel = lLRKernel;
                obj.HRKernel = lHRKernel;
            end
            obj.rf_indices_lr(end+1) = {IndexLR};
            obj.rf_indices_hr(end+1) = {IndexHR};
            obj.rf_models(end+1) = {'DKI'};
        end
        
        % Add an anisotropic RF based on the NODDI model. These can be
        % added only before any isotropic RF.
        % noddi_parameters(x) should be specified as follows:
        % x(1) is the volume fraction of the intracellular space.
        % x(2) is the free diffusivity of the material inside and outside the cylinders.
        % x(3) is the concentration parameter of the Watson's distribution.
        % x(4) is the volume fraction of the isotropic compartment.
        % x(5) is the diffusivity of the isotropic compartment.
        % x(6) is the measurement at b=0.;        
        function obj = AddAnisotropicRF_NODDI(obj,noddi_parameters)
            
            if(isempty(obj.data))
                warning('Cannot initialize RFs if data has not been set. Bailing out.');
                return
            end
            if(obj.n_isotropic ~= 0)
                warning('Please add all anisotropic RFs before any isotropic component.');
                return
            end
            obj.n_anisotropic = obj.n_anisotropic+1;
            [~,lLRKernel,lHRKernel] = mDRLMT_MakeNODDIKernel_multicomp(obj.data,obj.nDirections,noddi_parameters,[],1);
            IndexHR = size(obj.HRKernel,2)+1:size(obj.HRKernel,2)+obj.nDirections;
            IndexLR = size(obj.LRKernel,2)+1:size(obj.LRKernel,2)+size(lLRKernel,2);
            if(~isempty(obj.LRKernel))
                obj.LRKernel(:,IndexLR) = lLRKernel;
                obj.HRKernel(:,IndexHR) = lHRKernel;
            else
                obj.LRKernel = lLRKernel;
                obj.HRKernel = lHRKernel;
            end
            obj.rf_indices_lr(end+1) = {IndexLR};
            obj.rf_indices_hr(end+1) = {IndexHR};
            obj.rf_models(end+1) = {'NODDI'};
        end
        
        % Compute the automatic damping for the dRL method. Only needed if
        % the deconvolution method is dRL.
        function obj = AutomaticDRLDamping(obj)
            obj.NN_L = get_drl_nn_heuristic(obj.LRKernel,max(obj.data.bvals),0.7e-3);
            obj.NN_H = get_drl_nn_heuristic(obj.HRKernel,max(obj.data.bvals),0.7e-3);
        end
        
        % Actually perform the deconvolution. All parameters must be set
        % before hand using the dedicated functions. Output is a structure
        % with fields FOD and FOD_norm. FOD_norm is a rescaled version of the FOD 
        % meant to be compatible with ExploreDTI-based fiber tractography.
        function output = PerformDeconv(obj)
            
            if(~obj.isInitialized())
                warning('Not all conditions are met to perform the deconvolution. Make sure you setted all needed parameters.');
                output = [];
                return
            end
            
            if(~ismatrix(obj.data.img))
                siz = size(obj.data.img);
                obj.data.img = reshape(obj.data.img,siz(1)*siz(2)*siz(3),siz(4)); % st(133)* ~isnan(FA)
                obj.data.img = permute(obj.data.img,[2 1]);
            end
            [st,sm] = size(obj.data.img);
            
            NC = obj.n_isotropic;
            
            nreconstruction_vertices = size(obj.HRKernel,2)-NC;
            nreconstruction_vertices_lr = size(obj.LRKernel,2)-NC;
            
            fprintf('Determining NN: %.3f for LR and %.3f for HR %s',obj.NN_L, obj.NN_H, newline);
            
            shell_weight = zeros(size(obj.data.bvals));
            all_shells = (unique(obj.data.bvals));
            for ij=1:length(all_shells)
                this_shell = abs(obj.data.bvals-all_shells(ij)) < 100;
                shell_weight(this_shell) = ij;
            end
            
            shell_weight(shell_weight < length(all_shells)) = obj.inner_shells_weight;
            shell_weight(shell_weight == length(all_shells)) = 1;
            
            weighted_LRKernel = obj.LRKernel;
            weighted_HRKernel = obj.HRKernel;
            
            % Weighted kernels for the lower shells
            for ij=1:size(obj.LRKernel,2)
                weighted_LRKernel(:,ij) = obj.LRKernel(:,ij).*shell_weight;
            end
            
            for ij=1:size(obj.HRKernel,2)
                weighted_HRKernel(:,ij) = obj.HRKernel(:,ij).*shell_weight;
            end
            
            fractions = zeros([sm 3]);
            WM_fod = zeros([sm nreconstruction_vertices],'single');
            RSS = zeros([sm 1]);
            S0 = zeros([sm 1]);
            
            N = sm;
            op_e2 = optimset('TolX',1e-2);
            
            [~,DeconvMethodCode] = SphericalDeconvolution.isSupportedMethod(obj.deconv_method); % -1 = failure; 1 = LSQNONNEG; 2 = DW_RegularizedDeconv; 3 = dRL
            if(DeconvMethodCode == -1)
                warning('Unsupported deconvolution method.');
                return;
            end

            TheTol = 1e-3;
            tic
            parfor x=1:N
                %     if(mod(x,progressStepSize) == 0)
                %         ppm.increment();
                %     end
                if(obj.data.mask(x) < 1)
                    continue
                end
                
                Stot = double(obj.data.img(:,x));
                
                % This normalization assumes there is some b=0s/mm2 data. It is not
                % essential to do it as long as fractions is normalized at the end
                NormFactor = mean(Stot(obj.data.bvals<100));
                S0(x) = NormFactor;
                Stot = Stot/NormFactor;
                
                Stot = Stot.*shell_weight; % Weight the lower shells
                
                piso = zeros(NC,1);
                p_old = Inf; % store the fractions at previous iter
                
                % The following loop will iterate WM-FOD estimation (with mDRL) and
                % fractions guess (with LSQNONNEG)
                for iter=1:50 % 50 = max number of iterations but usually exits way before
                    
                    DS = max(Stot-weighted_LRKernel(:,end-NC+1:end)*piso,0); % Subtract GM and CSF contributions

                    if(DeconvMethodCode == 4)
%                         fODFC = mat_dRL(DS, weighted_LRKernel(:,1:end-NC), 200, obj.NN_L, 8);
                        fODFC = ADT_deconv_RLdamp_1D_noEP(DS, weighted_LRKernel(:,1:end-NC),200, obj.NN_H);
                    elseif(DeconvMethodCode == 3)
%                         fODFC = mat_RL(DS, weighted_LRKernel(:,1:end-NC), 200);
                        fODF = RichardsonLucy(DS, weighted_LRKernel(:,1:end-NC), 200);
                    elseif(DeconvMethodCode == 2)
                        fODFC = DW_RegularizedDeconv(weighted_LRKernel(:,1:end-NC),DS,op_e2,obj.L2LSQ_reg);
                    elseif(DeconvMethodCode == 1)
                        fODFC = lsqnonneg(weighted_LRKernel(:,1:end-NC),DS,op_e2);
                    end
                    % This line is quite tricky. It comes out of some trial and error
                    % but actually has the intent of eliminating 1) small contributions
                    % 2) flat - spread fods enforcing sparsity.
                    % Without this line the code DOESN'T work. (WM is over-estimated).
                    fODFC(fODFC < median(fODFC)) = 0;
                    
                    % Build a dictionary to fit the complete signal (Stot)
                    Y = [obj.LRKernel(:,1:end-NC)*fODFC obj.LRKernel(:,end-NC+1:end)]; % 3 columns (WM-SIGNAL GM-SIGNAL CSF-SIGNAL)
                    
                    if(sum(Y(:,1)) > 0) % i.e. if the FOD is non-zero
                        Y(:,1) = Y(:,1)/max(Y(:,1)); % Normalize WM signal
                    end
                    
                    p = lsqnonneg(Y,Stot./shell_weight,op_e2); % Compute the signal fractions
                    piso = p(end-NC+1:end);
                    
                    % if nothing changed compared to previous iter, exit. (Tol may need to be
                    % adjusted)
                    if(sum(abs(p-p_old) < TheTol) == 3)
                        break
                    end
                    p_old = p;
                end
                
                % NEW FINAL STEP 05/02/2018
                DS = max(Stot - weighted_HRKernel(:,end-NC+1:end)*piso,0); % Subtract GM and CSF contributions

                if(DeconvMethodCode == 4)
%                     fODF = mat_dRL(DS, weighted_HRKernel(:,1:end-NC),200, obj.NN_H, 8);
                    fODF = ADT_deconv_RLdamp_1D_noEP(DS, weighted_HRKernel(:,1:end-NC),200, obj.NN_H);
                elseif(DeconvMethodCode == 3)
%                     fODF = mat_RL(DS, weighted_HRKernel(:,1:end-NC), 200);
                    fODF = RichardsonLucy(DS, weighted_HRKernel(:,1:end-NC), 200);
                elseif(DeconvMethodCode == 2)
                    fODF = DW_RegularizedDeconv(weighted_HRKernel(:,1:end-NC),DS,op_e2, obj.L2LSQ_reg);
                elseif(DeconvMethodCode == 1)
                    fODF = lsqnonneg(weighted_HRKernel(:,1:end-NC),DS, op_e2);                    
                end
                fODFC = fODF;
                fODFC(fODFC < median(fODFC)) = 0;
                Y = [obj.HRKernel(:,1:end-NC)*fODFC obj.HRKernel(:,end-NC+1:end)]; % 3 columns (WM-SIGNAL GM-SIGNAL CSF-SIGNAL)
                if(sum(Y(:,1)) > 0) % i.e. if the FOD is non-zero
                    Y(:,1) = Y(:,1)/max(Y(:,1)); % Normalize WM signal
                end
                p = lsqnonneg(Y,Stot./shell_weight,op_e2); % Compute the signal fractions
                RSS(x) = sum((Stot-Y*p).^2);
                
                fractions(x,:) = p;
                WM_fod(x,:) = single(fODF);
            end
            toc
            
            % Restructure data
            
            fsum = sum(fractions,2);
            for ij=1:3
                fractions(:,ij) = fractions(:,ij) ./ (fsum+eps);
            end
            
            output.fractions = reshape(fractions,[siz(1:3),size(fractions,2)]);
            
            WM_fod_max = max(WM_fod,[],2);
            WM_fod_normalized = WM_fod;
            WM_fod_val = mean(WM_fod_max(fractions(:,1) > 0.7*max(WM_fod_max(:)))); % 20/12/2017
            for ij=1:size(WM_fod_normalized,2)
                WM_fod_normalized(:,ij) = WM_fod_normalized(:,ij) / WM_fod_val;% .* fractions(:,1); % 20/12/2017
            end
            
            output.RSS = reshape(RSS,siz(1:3));
            clear RSS;
            output.FOD = reshape(WM_fod,[siz(1:3),size(WM_fod,2)]);
            clear WM_fod;
            output.FOD_norm = reshape(WM_fod_normalized,[siz(1:3),size(WM_fod_normalized,2)]);
            clear WM_fod_normalized;
            
            obj.data.img = permute(obj.data.img,[2 1]);
            obj.data.img = reshape(obj.data.img,siz); % st(133)* ~isnan(FA)          
        end
        
        % Sets the deconvolution method
        function setDeconvMethod(obj,method)
           if(~SphericalDeconvolution.isSupportedMethod(method))
               warning('Unsupported deconvolution method.');
               return;
           end
           obj.deconv_method = method; 
        end
        
    end
    
    methods(Static)
        % List the supported deconvolution methods
        function methods = SupportedMethods()
            methods = {'LSQ','L2LSQ','RL','dRL'};
        end
        
        % Check whether a method is actually supported
        function [boolean,method_id] = isSupportedMethod(method)
            methods = SphericalDeconvolution.SupportedMethods();
            for method_id=1:length(methods)
                if(strcmpi(methods{method_id},method))
                    boolean = true;
                    return;
                end
            end
            boolean = false;
            method_id = -1;
        end
        
        % Save the content of a deconvolution structure to nifti. SpherDec
        % is an instance of this class, output is the structure returned
        % from PerformDeconv. file_prefix is the name without extension of
        % the desired outputs.
        function SaveOutputToNii(SpherDec,output,file_prefix)
            lmax = 16;
            super_scheme = gen_scheme(SpherDec.nDirections,lmax); % the reconstruction scheme. Change 300 to any number
            sh = SH(lmax,super_scheme.vert);

            fod_wm = sh.coef(output.FOD);

            DW_SaveVolumeLikeNii(fod_wm,SpherDec.data,[file_prefix '_CSD_FOD'],0);

            DW_SaveVolumeLikeNii(output.fractions,SpherDec.data,[file_prefix '_fractions'],0);
        end
        
        % Load diffusion data in the MRIToolkit format. Input:
        % nii_file: the .nii(gz) data file
        % bval: the .bval file
        % bvec: the .bvec file
        % mask: the associated mask (optional)
        function mrt_data = LoadNiiBvalBvec(varargin)
            coptions = varargin;
            file_in = GiveValueForName(coptions,'nii_file');
            if(isempty(file_in))
                error('Need to specify the input .nii file');
            end
            coptions = varargin;
            bval = GiveValueForName(coptions,'bval');
            if(isempty(bval))
                error('Need to specify the input .bval file');
            end
            coptions = varargin;
            bvec = GiveValueForName(coptions,'bvec');
            if(isempty(bvec))
                error('Need to specify the input .bvec file');
            end      
            mask = GiveValueForName(coptions,'mask');
            if(isempty(mask))
                mask = '';
            end      
            
            mrt_data = DW_LoadData(file_in,bvec,bval,mask);
            mrt_data.img = single(mrt_data.img);
            mrt_data.img = permute(mrt_data.img,[2 1 3 4]);
            mrt_data.img = flip(mrt_data.img,1);
            mrt_data.img = flip(mrt_data.img,2);
        end
        
        % Estimate the average eigenvalues and isotropic kurtosis in a
        % dataset to initialize the RF
        function [EigVal,IsoK] = EstimatedAverageEigval_IsoK(data)
            [sx,sy,sz,st] = size(data.img);
            signal_stack = reshape(data.img,sx*sy*sz,st);

            [G,WG,GoodIndexes] = DW_BuildDTMat(data,unique(data.bvals),1);
            Gt = G;
            G = [Gt(:,1:6) 1/6*(data.bvals*1e-3).^2 Gt(:,end)];

            msk = sum(signal_stack==0,2) == 0;
            p = zeros(length(signal_stack),8);
            K = zeros(length(signal_stack),1);
            autovals = zeros(length(signal_stack),3);
            parfor ij=1:length(signal_stack)
                if(msk(ij) < 1)
                    continue
                end
                S = signal_stack(ij,:)';
                if(sum(S==0) > 0)
                    continue
                end
                p1 = E_DTI_WLLS_WW(S,G)
                p(ij,:) = p1;%G\log(S); 
                if(sum(~isfinite(p(ij,:))) > 0)
                    continue
                end
                autoval = eig(D2Dtensor(p(ij,:)));
                autovals(ij,:) = sort(autoval,'descend');
                K(ij) = 1e-6*p1(end-1)/mean(autoval.^2);
            end

            p = reshape(p,sx,sy,sz,8);

            [~,m_FA,m_DEC,~,~,m_lambdas,eigenvectors] = DW_ComputeTensorMetrics(p,1:6);
            U = m_FA(:) > 0.7 & data.mask(:) > 0; 

            EigVal = mean(autovals(U > 0,:));
            EigVal(2:3) = mean(EigVal(2:3));
            IsoK = mean(K(U(:) > 0 & K(:) > 0 & K(:) < 4));
        end
    end
end

% Private function to parse input parameters
function keys = ParseInputKeys(input)
    keys = {};
    if(mod(length(input),2) ~= 0)
        warning('Incorrect input pairs');
        return;
    end
    keys = cell(length(input)/2,2);
    for key_id=1:2:length(input)
        keys(key_id,1) = {input{key_id}};
        keys(key_id,2) = {input{key_id+1}};
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

% Private function assembling the DTI/DKI kernels
function [bmat,LRKernel,HRKernel] = mDRLMT_MakeDKIKernel_multicomp(data,nreconstruction_vertices,lambdas,K,isoDs,shell_data)

shells = single(unique(int16(round(data.bvals)/1)*1)); % automatic detection of number of shells.
% This shell splitting works only for b-value spaced more than 100. To be fixed for other datasets.
ndirections = zeros(length(shells),1);
for ij=1:length(shells)
    ndirections(ij) = sum(abs(data.bvals-shells(ij))<1);
end


if(shell_data > 0)
    bmat = cell(length(shells),1); % bmat = [bvecs bvals]
    Kernel = cell(length(shells),1);
    Kernel_LR = cell(length(shells),1);
else
    bmat{1} = [data.bvecs data.bvals];
    Kernel = cell(1,1);
    Kernel_LR = cell(1,1);
end

super_scheme = gen_scheme(nreconstruction_vertices,4); % the reconstruction scheme. Change 300 to any number
HRKernel = zeros(sum(ndirections),nreconstruction_vertices+length(isoDs));
[phi, theta] = cart2sph(super_scheme.vert(:,1),super_scheme.vert(:,2),super_scheme.vert(:,3)); % polar decomposition
lr_scheme = gen_scheme(min(length(data.bvals),90),4);
[phi_LR, theta_LR] = cart2sph(lr_scheme.vert(:,1),lr_scheme.vert(:,2),lr_scheme.vert(:,3));
LRKernel = zeros(sum(ndirections),size(lr_scheme.vert,1)+length(isoDs));

if(shell_data > 0)
    
    bvals = zeros(sum(ndirections),1);
    
    index = 1;
    
    for ij=1:length(shells)
        bmat{ij} = zeros(ndirections(ij),4);
        bmat{ij}(:,4) = shells(ij);
        bmat{ij}(:,1:3) = data.bvecs(index:index+ndirections(ij)-1,:);
        
        % Here the deconvolution dictionary is actually built
        Kernel{ij} = zeros(ndirections(ij),length(phi));
        for i=1:length(phi)
            anglesFi = [phi(i), theta(i)]*(180/pi); % in degrees
            Kernel{ij}(:,i) = create_signal_multi_tensor_dki(anglesFi, 1, lambdas, ...
                bmat{ij}(:,4), bmat{ij}(:,1:3), 1, 0, 0, K);
        end
        for l=1:length(isoDs)
            Kernel{ij}(:,end+1) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
                bmat{ij}(:,4), bmat{ij}(:,1:3), 1, 0, 0);
        end
        
        Kernel_LR{ij} = zeros(ndirections(ij),length(phi_LR));
        for i=1:length(phi_LR)
            anglesFi = [phi_LR(i), theta_LR(i)]*(180/pi); % in degrees
            Kernel_LR{ij}(:,i) = create_signal_multi_tensor_dki(anglesFi, 1, lambdas, ...
                bmat{ij}(:,4), bmat{ij}(:,1:3), 1, 0, 0, K);
        end
        for l=1:length(isoDs)
            Kernel_LR{ij}(:,end+1) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
                bmat{ij}(:,4), bmat{ij}(:,1:3), 1, 0, 0);
        end
        
        bvals(index:index+ndirections(ij)-1) = bmat{ij}(:,4);
        HRKernel(index:index+ndirections(ij)-1,:) = Kernel{ij};
        LRKernel(index:index+ndirections(ij)-1,:) = Kernel_LR{ij};
        
        % Just for the simulated signal - not needed in production version
        %    R = eye(3,3);
        %    D = diag(lambdas);
        %    S_WM = exp(-bmat{ij}(:,4).*diag(bmat{ij}(:,1:3)*R*D*R'*bmat{ij}(:,1:3)'));
        %    S_GM = exp(-bmat{ij}(:,4)*D_gm);
        %    S_CSF = exp(-bmat{ij}(:,4)*D_csf);
        %    S{ij} = f_wm*S_WM+f_gm*S_GM+f_csf*S_CSF;
        %    Ssim(index:index+ndirections(ij)-1) = S{ij};
        
        %
        index = index+ndirections(ij);
    end
    
else
    N = length(data.bvals);
    bmat{1} = zeros(N,4);
    bmat{1}(:,1:3) = data.bvecs;
    bmat{1}(:,4) = data.bvals;
    
    for i=1:length(phi)
        anglesFi = [phi(i), theta(i)]*(180/pi); % in degrees
        HRKernel(:,i) = create_signal_multi_tensor_dki(anglesFi, 1, lambdas, ...
            bmat{1}(:,4), bmat{1}(:,1:3), 1, 0, 0, K);
    end
    for l=1:length(isoDs)
        HRKernel(:,length(phi)+l) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
            bmat{1}(:,4), bmat{1}(:,1:3), 1, 0, 0);
    end
    
    for i=1:length(phi_LR)
        anglesFi = [phi_LR(i), theta_LR(i)]*(180/pi); % in degrees
        LRKernel(:,i) = create_signal_multi_tensor_dki(anglesFi, 1, lambdas, ...
            bmat{1}(:,4), bmat{1}(:,1:3), 1, 0, 0, K);
    end
    for l=1:length(isoDs)
        LRKernel(:,length(phi_LR)+l) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
            bmat{1}(:,4), bmat{1}(:,1:3), 1, 0, 0);
    end    
end

end

% Private function assembling the NODDI based kernels.
function [bmat,LRKernel,HRKernel,super_scheme] = mDRLMT_MakeNODDIKernel_multicomp(data,nreconstruction_vertices,noddi_values,isoDs,shell_data)
if(isempty(which('SynthMeasWatsonSHStickTortIsoV_B0')))
    error('Cannot find the NODDI toolbox. Please, add it to the MATLAB path');
end
    
shells = single(unique(int16(round(data.bvals)/1)*1)); % automatic detection of number of shells.
% This shell splitting works only for b-value spaced more than 100. To be fixed for other datasets.
ndirections = zeros(length(shells),1);
for ij=1:length(shells)
    ndirections(ij) = sum(abs(data.bvals-shells(ij))<1);
end

bvals = data.bvals';
save('temp_bvals.bval','bvals','-ascii');
bvecs = data.bvecs';
% bvecs(:,1) = -bvecs(:,1);
% bvecs(:,3) = -bvecs(:,3);
save('temp_bvecs.bvec','bvecs','-ascii');
clear bvals bvecs
NODDI_protocol = FSL2Protocol('temp_bvals.bval','temp_bvecs.bvec');
delete('temp_bvals.bval');
delete('temp_bvecs.bvec');

lr_nreconstruction_vertices = min(length(data.bvals),90);

if(shell_data > 0)
    bmat = cell(length(shells),1); % bmat = [bvecs bvals]
    Kernel = cell(length(shells),1);
    Kernel_LR = cell(length(shells),1);
else
    bmat{1} = [data.bvecs data.bvals];
    Kernel = cell(1,1);
    Kernel_LR = cell(1,1);
end

% nreconstruction_vertices = 300; % 20/12/2017
nlr_vert = 0;
nhr_vert = sum(nreconstruction_vertices);

for ij=1:length(nreconstruction_vertices)
    super_scheme{ij} = gen_scheme(nreconstruction_vertices(ij),4); % the reconstruction scheme. Change 300 to any number
    [phi{ij}, theta{ij}] = cart2sph(super_scheme{ij}.vert(:,1),super_scheme{ij}.vert(:,2),super_scheme{ij}.vert(:,3)); % polar decomposition
    lr_scheme{ij} = gen_scheme(min(length(data.bvals),lr_nreconstruction_vertices(ij)),4);
    [phi_LR{ij}, theta_LR{ij}] = cart2sph(lr_scheme{ij}.vert(:,1),lr_scheme{ij}.vert(:,2),lr_scheme{ij}.vert(:,3));
    
    nlr_vert = nlr_vert + size(lr_scheme{ij}.vert,1);
end

HRKernel = zeros(sum(ndirections),nhr_vert+length(isoDs));
LRKernel = zeros(sum(ndirections),nlr_vert+length(isoDs));
% S = cell(length(shells),1);
% Ssim = zeros(sum(ndirections),1); % Just a simulated signal for internal testing

% noddi_values = [1 1.7E-9 3.5 0 3E-9 1];% x is the list of model parameters in SI units:
% % x(1) is the volume fraction of the intracellular space.
% % x(2) is the free diffusivity of the material inside and outside the cylinders.
% % x(3) is the concentration parameter of the Watson's distribution.
% % x(4) is the volume fraction of the isotropic compartment.
% % x(5) is the diffusivity of the isotropic compartment.
% % x(6) is the measurement at b=0.;

if(shell_data > 0)
    
    bvals = zeros(sum(ndirections),1);
    
    index = 1;
    
    for ij=1:length(shells)
        bmat{ij} = zeros(ndirections(ij),4);
        bmat{ij}(:,4) = shells(ij);
        bmat{ij}(:,1:3) = data.bvecs(index:index+ndirections(ij)-1,:);
        
        % Here the deconvolution dictionary is actually built
        
        % ANISOTROPIC PART
        hr_index_columns = 0;
        lr_index_columns = 0;
        
        Kernel{ij} = zeros(ndirections(ij),nhr_vert);
        Kernel_LR{ij} = zeros(ndirections(ij),nlr_vert);
        for aniso_comp = 1:length(nreconstruction_vertices)
            % HR
            for i=1:length(phi{aniso_comp})
                fibredir = super_scheme{aniso_comp}.vert(i,:)';
                E = SynthMeasWatsonSHStickTortIsoV_B0(noddi_values{aniso_comp}, NODDI_protocol, fibredir);
                Kernel{ij}(:,i+hr_index_columns) = E;
            end

            % LR
            for i=1:length(phi_LR{aniso_comp})
                fibredir = lr_scheme{aniso_comp}.vert(i,:)';
                E = SynthMeasWatsonSHStickTortIsoV_B0(noddi_values{aniso_comp}, NODDI_protocol, fibredir);
                Kernel_LR{ij}(:,i+lr_index_columns) = E;
            end
            
            hr_index_columns = hr_index_columns + size(super_scheme{aniso_comp}.vert,1);
            lr_index_columns = hr_index_columns + size(lr_scheme{aniso_comp}.vert,1);
        end
        
        % ISOTROPIC PART
        % HR
        for l=1:length(isoDs)
            Kernel{ij}(:,end+1) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
                bmat{ij}(:,4), bmat{ij}(:,1:3), 1, 0, 0);
        end        
        
        % LR
        for l=1:length(isoDs)
            Kernel_LR{ij}(:,end+1) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
                bmat{ij}(:,4), bmat{ij}(:,1:3), 1, 0, 0);
        end
        
        % Build a linear dictionary with the subparts
        bvals(index:index+ndirections(ij)-1) = bmat{ij}(:,4);
        HRKernel(index:index+ndirections(ij)-1,:) = Kernel{ij};
        LRKernel(index:index+ndirections(ij)-1,:) = Kernel_LR{ij};
        
        index = index+ndirections(ij);
    end
    
else
    N = length(data.bvals);
    bmat{1} = zeros(N,4);
    bmat{1}(:,1:3) = data.bvecs;
    bmat{1}(:,4) = data.bvals;

    % ANISOTROPIC PART
    hr_index_columns = 0;
    lr_index_columns = 0;
    for aniso_comp = 1:length(nreconstruction_vertices)
        
        % HR
        for i=1:length(phi{aniso_comp})
            fibredir = super_scheme{aniso_comp}.vert(i,:)';
            E = SynthMeasWatsonSHStickTortIsoV_B0(noddi_values{aniso_comp}, NODDI_protocol, fibredir);
            HRKernel(:,i+hr_index_columns) = E;
        end
        %LR
        for i=1:length(phi_LR{aniso_comp})
            fibredir = lr_scheme{aniso_comp}.vert(i,:)';
            E = SynthMeasWatsonSHStickTortIsoV_B0(noddi_values{aniso_comp}, NODDI_protocol, fibredir);
            LRKernel(:,i+lr_index_columns) = E;
        end
        
        hr_index_columns = hr_index_columns + size(super_scheme{aniso_comp}.vert,1);
        lr_index_columns = lr_index_columns + size(lr_scheme{aniso_comp}.vert,1);        
    end
    % ISOTROPIC PART
    % HR
    for l=1:length(isoDs)
        HRKernel(:,hr_index_columns+l) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
            bmat{1}(:,4), bmat{1}(:,1:3), 1, 0, 0);
    end
    % LR
    for l=1:length(isoDs)
        LRKernel(:,lr_index_columns+l) = create_signal_multi_tensor([0 0], 1, [isoDs(l) isoDs(l) isoDs(l)], ...
            bmat{1}(:,4), bmat{1}(:,1:3), 1, 0, 0);
    end    
end

end

% The following functions have been included from "hardi_tools", which is
% available as follows: 
% Original authors:
%% Project:   High Angular Resolution Diffusion Imaging Tools
% Available at: https://www.neuroimagen.es/webs/hardi_tools/
% Function to create a simulated signal from the multi-tensor diffusion model.
% Rician noise can be added.                                                                        
%                                                                                                
%   Language:  MATLAB(R)
%   Author:  Erick Canales-Rodríguez, Lester Melie-García, Yasser Iturria-Medina, Yasser Alemán-Gómez
%   Date: 2013, Version: 1.2          
% 
% See also test_DSI_example, test_DOT_example, test_QBI_example,
% test_DOT_R1_example, test_DOT_R2_vs_CSA_QBI_example.                           

% Modifications have been performed where needed for compatibility (from
% A. De Luca)
function [S, D] = create_signal_multi_tensor (ang, f, Eigenvalues, b, grad, S0, SNR, add_noise)
% -Normalizing the gradient vector and then transforming the b-value.
% -This part is only for non-unitary gradient vectors
% Transform_b_value_and_grad = repmat(sqrt(diag(grad*grad')+eps), [1 3]);
% grad = grad./Transform_b_value_and_grad;
% b = b.*(Transform_b_value_and_grad(:,1)).^2;

A = diag(Eigenvalues);

S = 0;
Nfibers = length(f);
f = f/sum(f);
for i = 1:Nfibers
    phi(i) = ang(i, 1);
    theta(i) = ang(i, 2);
    R = RotMatrix(phi(i),theta(i));
    D = R*A*R';
    S = S + f(i)*exp(-b.*diag(grad*D*grad'));
end
S = S0*S;

sigma = S0/SNR;

standar_deviation = sigma.*(ones(length(grad),1));
med = zeros(length(grad),1);

er1 = normrnd(med, standar_deviation);
er2 = normrnd(med, standar_deviation);

if add_noise == 1
    S = sqrt((S + er1).^2 + er2.^2);
end

return
end

% Extension to DKI - A. De Luca
function [S, D] = create_signal_multi_tensor_dki (ang, f, Eigenvalues, b, grad, S0, SNR, add_noise, K)
% -Normalizing the gradient vector and then transforming the b-value.
% -This part is only for non-unitary gradient vectors
% Transform_b_value_and_grad = repmat(sqrt(diag(grad*grad')+eps), [1 3]);
% grad = grad./Transform_b_value_and_grad;
% b = b.*(Transform_b_value_and_grad(:,1)).^2;

A = diag(Eigenvalues);

S = 0;
Nfibers = length(f);
f = f/sum(f);
b2D2K = 1/6*b.^2.*mean(Eigenvalues.^2)*K;
for i = 1:Nfibers
    phi(i) = ang(i, 1);
    theta(i) = ang(i, 2);
    R = RotMatrix(phi(i),theta(i));
    D = R*A*R';
    S = S + f(i)*exp(-b.*diag(grad*D*grad')+b2D2K);
end
S = S0*S;

sigma = S0/SNR;

standar_deviation = sigma.*(ones(length(grad),1));
med = zeros(length(grad),1);

er1 = normrnd(med, standar_deviation);
er2 = normrnd(med, standar_deviation);

if add_noise == 1
    S = sqrt((S + er1).^2 + er2.^2);
end
end

% --- private funtions -----------
function R = RotMatrix(phi,theta)

c = pi/180;
phi = phi*c;
theta = theta*c;

Rz = [ cos(phi)  -sin(phi)  0
       sin(phi)   cos(phi)  0
           0         0      1];


Ry = [cos(theta)   0   sin(theta)
          0        1         0
     -sin(theta)   0   cos(theta)];

R =  Rz*Ry;
return
end

function scheme = gen_scheme(N, lmax)

% function scheme = gen_scheme(N, lmax)
%
% Generate a set of orientations in the required format, along
% with the corresponding SH transform information up to 
% harmonic order 'lmax'.
%
% If N is a string, it will attempt to load the specified
% file.
%
% If N is a number, a scheme with the specified number of
% directions will be generated using the equidistribute.m 
% script (note that these are not perfectly uniformly
% distributed).
%
% If N is a nx3 matrix, it will assume that each row provides
% an [ x y z ] vector pointing along the desired direction.
% 

if ischar(N)
  N = load(N);
end

if size(N,1) == 1 & size(N,2) == 1
  P = c2s(equidistribute(N));
elseif size(N,2) >= 3
  n = sqrt(sum(N(:,1:3).^2,2));
  k = find(n);
  X = N(k,1:3)./repmat(n(k),1,3);
  P = c2s(X);
else
  P = N;
end

scheme.el = P(:,1);
scheme.az = P(:,2);

scheme.sh = [];
scheme.lmax = lmax;

for l = 0:2:lmax
  scheme.sh = [ scheme.sh eval_SH(l, scheme.el, scheme.az)' ];
end

scheme.vert= s2c([ scheme.el scheme.az 1+0*scheme.az]);
scheme.mesh = convhulln(scheme.vert);
end

function s = eval_ALP(l, el)

% syntax: s = eval_ALP(l, el)
%
% evaluates the Associated Legendre Polynomial at elevations 'el'
% for harmonic order l.

  s = legendre(l, cos(el'));
  for m = 0:l
    s(m+1,:) = s(m+1,:).*sqrt((2*l+1)*factorial(l-m) / ((4*pi)*factorial(l+m)));
  end

  if l
    s = [ s(end:-1:2,:); s ];
  end
end

function s = eval_SH(l, el, az)

% syntax: s = eval_SH(l, el, az)
%
% Evaluates the lth order spherical harmonic coefficients at
% positions [ el az ].

s = ones(size(az,1),1);

if l > 0  
  s = [ sqrt(2)*sin(az*(l:-1:1)) s sqrt(2)*cos(az*(1:l)) ];
end

s = eval_ALP(l, el).*s';
end

function X = equidistribute(N)
% X = equidistribute(N)
% uses the formula in [saff:dmp:1997] to generate equidistributed
% points on the sphere.
% INPUT: N is the number of points, default=12
% 
% OUTPUT: X is the set of points as a Nxd matrix, one point per row
%         if no output is specified, the points are plotted using scatter3.
% REFERENCE
% @Article{saff:dmp:1997,
%  author =          {Saff, E. B. and Kuijlaars, A. B. J.},
%  title =          {Distributing Many Points on a Sphere},
%  journal =          {Math. Intell.},
%  year =          {1997},
%  volume =          {19},
%  number =          {1},
%  pages =          {5--11},
%}


X = zeros(N,3);

for k=1:N
  h = -1 + 2*(k-1)/(N-1);
  theta(k) = acos(h);
  if k==1 | k==N 
    phi(k) = 0;
  else 
    phi(k) = mod(phi(k-1) + 3.6/sqrt(N*(1-h^2)),2*pi);
  end;
  X(k,:) = [ cos(phi(k))*sin(theta(k)), ...
	     sin(phi(k))*sin(theta(k)), ...
	     cos(theta(k)) ];
end;

%if nargout == 0
  %Z = zeros(size(X));
  %[SX,SY,SZ] = sphere;
  %scatter3(X(:,1),X(:,2),X(:,3),'filled')
  %hold on
  %sph2 = surf(SX,SY,SZ);
  %set(sph2, 'FaceColor', [ 1 1 0 ]);
  %axis vis3d
%end
end

% Taken from "hardi tools" of Erick Canales-Rodriguez
function fODF = ADT_deconv_RLdamp_1D_noEP(Signal, Kernel, Niter,nu)
% fODF: purely anisotropic part

fODF0 = ones(size(Kernel,2),1);

fODF = fODF0/sum(fODF0);
KernelT = Kernel'; % only one time

fzero = 1e-06;
KernelS = KernelT*Signal;
V = 8;

mu = max(0, 1 - 4*std(Signal) );
nuV = nu^V;
last_odf = fODF;
my_eps = 1e-4*max(Signal);
for i = 1:Niter
    % --- approach: Flavio Dell’Acqua
    Dem = KernelT*(Kernel*fODF);
    fODFV = fODF.^V;
    Rk = 1 - (fODFV)./(fODFV + nuV);
    Uk = 1 - mu*Rk;
    RL_factor = 1 + Uk.*( (KernelS-Dem)./(Dem + eps) );
    fODF = max(fzero, fODF.*RL_factor); % positivity
    if(sum(abs(fODF-last_odf)) <= my_eps)
        break
    end
    last_odf = fODF;
end


end

function fODF = RichardsonLucy(Signal, Kernel, Niter)

fODF0 = ones(size(Kernel,2),1);

fODF = fODF0/sum(fODF0);
KernelT = Kernel'; % only one time

KernelS = KernelT*Signal;

last_odf = fODF;
my_eps = 1e-4*max(Signal);
for i = 1:Niter
    Dem = KernelT*Kernel*fODF;
    fODF = fODF.*(KernelS./(Dem+eps));
    if(sum(abs(fODF-last_odf)) <= my_eps)
        break
    end
    last_odf = fODF;
end


end

function nn_val = get_drl_nn_heuristic(bh,bvalue,tgt_diffusivity)
    if(nargin < 3)
        tgt_diffusivity = 0.7e-3;
    end
    S = exp(-bvalue*tgt_diffusivity)*ones(size(bh,1),1);
    K = RichardsonLucy(S,bh,200);
    nn_val = max(K)*2;
end