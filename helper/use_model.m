function use_model(which)
% use_model('pinn') | use_model('ann') | use_model('fp')
w = lower(string(which));
if ~ismember(w, ["pinn" "ann" "fp"])
    error('Use ''pinn'', ''ann'' or ''fp''.');
end
setappdata(0, 'NMPC_MODEL', char(w));
fprintf('NMPC prediction model: %s\n', upper(w));
end