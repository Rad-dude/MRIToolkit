%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%%%% Alberto De Luca - alberto@isi.uu.nl $%%%%%% Distributed under the terms of LGPLv3  %%%
%%% Distributed under the terms of LGPLv3  %%%
% A. De Luca
% This function adds the specified toolboxes to the path. If no input is
% specified all toolboxes will be added
% 29/03/2018: creation - v1.0
% 23/09/2018: addition of ThirdParty, OptimizationMethods, Relaxometry
% 09/11/2019: Change of name - added the - ExploreDTIInterface
function MRIToolkitInit(SelectedToolboxes)
    run_folder = mfilename('fullpath');
    if(~isempty(run_folder))
        if(ispc)
            slash_location = strfind(run_folder,'\');
        else
            slash_location = strfind(run_folder,'/');
        end
        run_folder = run_folder(1:slash_location(end)-1);
    else
        run_folder = pwd;
    end
    addpath(fullfile(run_folder,'init'));

    global MRIToolkit;
    clear MRIToolkit;
    MRIToolkit.version = 1.0;

    try
       MRIToolkitDefineLocalVars();
    catch
        disp('I cannot find a configuration file. Please define one');
    end

    available_toolboxes = {
        {'NiftiIO_basic','Manages basic Nifti input/output',true},...
        {'DW_basic','Basic diffusion MRI utils',true},...
        {'ImageRegistrations','Elastix based registration utils',true},...
        {'ThirdParty','Third party utilities',true},...
        {'OptimizationMethods','Class for numeric optimization',true},...
        {'Relaxometry','Class for T1/T2 quantification',true},...
        {'ExploreDTIInterface','ExploreDTI powered library',true},...
        {'SphericalDeconvolution','Methods to perform GRL/mFOD deconvolution',true}
        }; % Folder, Description, Load default

    if(nargin > 0 && ~iscell(SelectedToolboxes))
        disp('Usage 1: MRIToolkitInit() -> load all toolboxes');
        disp('Usage 2: MRIToolkitInit({''Identifier1'',...)');
        disp('Possible identifiers:');
        for ij=1:length(available_toolboxes)
           disp([available_toolboxes{ij}{1} ': ' available_toolboxes{ij}{2}]);
        end
        return
    end

    run_folder = get_executed_file_path();

    % Add all toolboxes if no input is specified
    if(nargin < 1)
        SelectedToolboxes = available_toolboxes;
        override_default = false;
    else
        UserSpecifiedToolboxes = SelectedToolboxes;
        override_default = true;
        warning('off');
        disp('Deactivating previously initialized toolboxes (if any)');
        for tool_id=1:length(available_toolboxes)
            run(fullfile(run_folder,available_toolboxes{tool_id}{1},'mk_deinit.m'));
        end
        warning('on');
        SelectedToolboxes = cell(length(UserSpecifiedToolboxes),1);
        for tool_id=1:length(SelectedToolboxes)
            toolbox_found = 0;
            for av_id=1:length(available_toolboxes)
               if(strcmpi(UserSpecifiedToolboxes{tool_id},available_toolboxes{av_id}{1}))
                  toolbox_found = av_id;
                  break
               end
            end
           if(toolbox_found > 0)
              SelectedToolboxes{tool_id} = available_toolboxes{toolbox_found};
           else
              disp(['The specified toolbox (' UserSpecifiedToolboxes{tool_id} ') does not exist. Quitting.']);
              return
           end
        end
    end

    for tool_id=1:length(SelectedToolboxes)
        % Call the init function of each toolbox
        if(SelectedToolboxes{tool_id}{3} || override_default)
            disp(['Adding ' SelectedToolboxes{tool_id}{1} ' (' SelectedToolboxes{tool_id}{2} ') to the path']);
            run(fullfile(run_folder,SelectedToolboxes{tool_id}{1},'mk_init.m'));
        end
    end

end