%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%



% A. De Luca
% Sub-toolbox specific initialization
% 29/03/2018: creation - v1.0
global MRIToolkit;
MRIToolkit.image_registrations_version = 1.0;

addpath(get_executed_file_path())
addpath(fullfile(get_executed_file_path(),'elastix_parameters'))