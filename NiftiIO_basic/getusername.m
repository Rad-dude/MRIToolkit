%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%%%% Alberto De Luca - alberto@isi.uu.nl $%%%%%% Distributed under the terms of LGPLv3  %%%
%%% Distributed under the terms of LGPLv3  %%%
function userName = getusername
%GETUSERNAME  Get user name.
%		USERNAME = GETUSERNAME returns the login name of the current MATLAB
%		user. Function should work for both Linux and Windows.
%
%		Markus Buehren
%		Last modified: 10.04.2009
%
%		See also GETHOSTNAME.

persistent userNamePersistent

if isempty(userNamePersistent)
  if ispc
    userName = getenv('username');
  else
    userName = getenv('USER');
    if isempty(userName)
      % environment variable not existing
      systemCall = 'whoami';
      [status, userName] = system(systemCall); %#ok
      if status ~= 0
        error('System call ''%s'' failed with return code %d.', systemCall, status);
      end
      userName = userName(1:end-1);
    end
  end

  % save string for next function call
  userNamePersistent = userName;
else
  % return string computed before
  userName = userNamePersistent;
end