function pubify(name, w, h)
%PUBIFY  Takes the current figure (e.g. from Scope > File > Print to Figure),
%        formats it for the journal and saves it as vector PDF + 600 dpi PNG.
%
%   pubify('tt_servo')            % 6.5 x 3.6 in (full page width)
%   pubify('tt_solver', 3.2, 2.6) % half width, for panels side by side
%
% Output: PINN_THREE_TANK/figures_pub/<name>.pdf and .png

if nargin < 2, w = 6.5; end
if nargin < 3, h = 3.6; end
f = gcf;
set(f, 'Color', 'w', 'Units', 'inches', 'Position', [1 1 w h], ...
       'InvertHardcopy', 'off', 'Renderer', 'painters');

% Colour-blind-safe set: black plant/setpoint, blue, vermillion, green, orange, purple
C = [0 0 0; 0 114 178; 213 94 0; 0 158 115; 230 159 0; 204 121 167] / 255;

ax = findall(f, 'Type', 'axes');
for a = ax'
    set(a, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'GridColor', [0.85 0.85 0.85], ...
        'FontName', 'Times New Roman', 'FontSize', 9, 'LineWidth', 0.6, ...
        'TickDir', 'in', 'Box', 'on', 'XGrid', 'off', 'YGrid', 'off');
    a.Title.Color = 'k'; a.Title.FontWeight = 'normal'; a.Title.FontSize = 9;
    a.XLabel.Color = 'k'; a.YLabel.Color = 'k';
    ln = flipud(findall(a, 'Type', 'line'));   % in plotting order
    for k = 1:numel(ln)
        ln(k).Color = C(mod(k - 1, size(C, 1)) + 1, :);
        ln(k).LineWidth = 1.0;
    end
end
lg = findall(f, 'Type', 'legend');
for l = lg'
    set(l, 'Color', 'w', 'TextColor', 'k', 'EdgeColor', 'none', ...
        'FontName', 'Times New Roman', 'FontSize', 8, 'Box', 'off');
end

out = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'figures_pub');
if ~exist(out, 'dir'), mkdir(out); end
exportgraphics(f, fullfile(out, [name '.pdf']), 'ContentType', 'vector', 'BackgroundColor', 'white');
exportgraphics(f, fullfile(out, [name '.png']), 'Resolution', 600, 'BackgroundColor', 'white');
fprintf('Saved %s (.pdf, .png) in %s\n', name, out);
end
