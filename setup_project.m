%% setup_project.m - run this from the PINN_THREE_TANK folder first
root = fileparts(mfilename('fullpath'));
folders = {'base','helper','data','python', ...
           fullfile('python','weights'),'models','control'};
for i = 1:numel(folders)
    p = fullfile(root, folders{i});
    if ~exist(p,'dir'), mkdir(p); fprintf('created %s\n', folders{i}); end
end
addpath(fullfile(root,'base'), fullfile(root,'helper'));
savepath;
cd(root);
fprintf('\nProject ready. Path includes base/ and helper/.\n');