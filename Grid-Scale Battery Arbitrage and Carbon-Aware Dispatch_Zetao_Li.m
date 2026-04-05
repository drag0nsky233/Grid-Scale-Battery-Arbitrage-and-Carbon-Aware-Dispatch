% EGS Coursework - Case B: Grid Scale Battery with Carbon-aware Dispatch
% Author: Zetao Li  k25022814@kcl.ac.uk
% Extension: Carbon-aware Dispatch — Lambda Parameter Sweep & Pareto Analysis
% [Objective Function Correction]
% Fix: f_dis = -price (discharge only receives price revenue, no carbon credit)
%   Carbon penalty only applies to charging. This ensures charging emissions
%   monotonically decrease as lambda increases, aligning with physical laws.
%
% [Carbon Emission Metrics]
%   Gross Emissions = Σ P_ch(t)*carbon(t)*dt (Always positive, baseline for reduction)
%   Net Emissions = Σ (P_ch-P_dis)(t)*carbon(t)*dt (Can be negative, indicates grid impact)

clear; clc; close all;


%  Stage 1: Data Load & Unit Conversion
fprintf('======================================================\n');
fprintf('--- Stage 1: Data Preparation & Parameter Setup ---\n');

data = readtable('caseB_grid_battery_market_hourly.csv');
price_gbp_mwh = data.day_ahead_price_gbp_per_mwh;           % Unit: GBP/MWh
carbon_kg_kwh = data.carbon_intensity_kg_per_kwh_optional;  % Unit: kg/kWh

% Explicit unit conversion: 1 MWh = 1000 kWh
carbon_kg_mwh = carbon_kg_kwh * 1000;  % Convert to kg/MWh

T  = length(price_gbp_mwh);
dt = 1; % Time step: 1 hour

fprintf('Data rows (T) : %d hours (%.0f days)\n', T, T/24);
fprintf('Carbon range  : %.1f ~ %.1f kg/MWh\n', min(carbon_kg_mwh), max(carbon_kg_mwh));
fprintf('Price range   : %.2f ~ %.2f GBP/MWh\n', min(price_gbp_mwh), max(price_gbp_mwh));
fprintf('Unit check    : carbon(1)=%.4f kg/kWh -> %.2f kg/MWh\n', carbon_kg_kwh(1), carbon_kg_mwh(1));


%  Stage 2: Battery Physical Parameters
E_max   = 2;            % Max capacity MWh
P_max   = 1;            % Max power MW
eta_rt  = 0.88;         % Round-trip efficiency 88%
eta_ch  = sqrt(eta_rt); % Charging efficiency
eta_dis = sqrt(eta_rt); % Discharging efficiency
E0      = 0.5 * E_max;  % Initial SOC = 50%

fprintf('\n[Battery Physical Parameters]\n');
fprintf('  Max Capacity (E_max) : %.2f MWh\n', E_max);
fprintf('  Max Power (P_max)    : %.2f MW\n', P_max);
fprintf('  Efficiency           : RT %.2f%%, Ch %.4f, Dis %.4f\n', eta_rt*100, eta_ch, eta_dis);
fprintf('  Initial SOC (E0)     : %.2f MWh (%.0f%%)\n', E0, E0/E_max*100);
fprintf('======================================================\n');


%  Stage 3: Build LP Constraints
%  Decision variables: x = [P_ch; P_dis; E], size 3T x 1
% Variable bounds
lb = [zeros(T,1); zeros(T,1); zeros(T,1)];
ub = [P_max*ones(T,1); P_max*ones(T,1); E_max*ones(T,1)];
lb(3*T) = E0;  % Final SOC lower bound: E(T) >= E0

% Energy balance equality constraints: Aeq * x = beq
% E(t) - E(t-1) - eta_ch*P_ch(t)*dt + (1/eta_dis)*P_dis(t)*dt = 0
Aeq = zeros(T, 3*T);
beq = zeros(T, 1);
for t = 1:T
    Aeq(t, t)         = -eta_ch * dt;       % P_ch(t)
    Aeq(t, T + t)     = (1/eta_dis) * dt;   % P_dis(t)
    Aeq(t, 2*T + t)   = 1;                  % E(t)
    if t == 1
        beq(t) = E0;                         % Initial condition
    else
        Aeq(t, 2*T + t - 1) = -1;           % E(t-1)
    end
end


%  Stage 4: Lambda Parameter Sweep — Multi-objective Optimization
%  Objective (Minimize): f_ch^T * P_ch + f_dis^T * P_dis
lambda_values = [0, 0.01, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0];
num_cases     = length(lambda_values);

results_profit          = zeros(num_cases, 1);
results_gross_emissions = zeros(num_cases, 1); % Always positive
results_net_emissions   = zeros(num_cases, 1); % Can be negative
results_throughput      = zeros(num_cases, 1);

options = optimoptions('linprog', 'Display', 'off');

fprintf('\n--- Stage 4: Lambda Parameter Sweep ---\n');

for i = 1:num_cases
    lambda = lambda_values(i);
    
    % Objective function setup
    % Charge: Electricity cost + Carbon penalty
    f_ch  = price_gbp_mwh + lambda .* carbon_kg_mwh;
    % Discharge: Price revenue only (no carbon credit to prevent false arbitrage)
    f_dis = -price_gbp_mwh;
    
    f = [f_ch; f_dis; zeros(T, 1)];
    
    % Solve LP
    [x, ~, exitflag] = linprog(f, [], [], Aeq, beq, lb, ub, options);
    
    if exitflag ~= 1
        error('Solver failed for lambda = %f. Check data or constraints.', lambda);
    end
    
    % Extract variables
    P_ch  = x(1:T);
    P_dis = x(T+1:2*T);
    E     = x(2*T+1:end);
    
    % KPI Calculation
    profit = sum((P_dis - P_ch) .* price_gbp_mwh) * dt;
    gross_emissions = sum(P_ch .* carbon_kg_mwh) * dt;
    net_emissions = sum((P_ch - P_dis) .* carbon_kg_mwh) * dt;
    throughput = sum(P_ch + P_dis) * dt / 2;
    
    results_profit(i)          = profit;
    results_gross_emissions(i) = gross_emissions;
    results_net_emissions(i)   = net_emissions;
    results_throughput(i)      = throughput;

    %  Base Case (lambda=0) Validation

    if lambda == 0
        fprintf('\n--- Stage 5: Base Case (lambda=0) Validation ---\n');
        fprintf('[Base Case Results]\n');
        fprintf('  Profit            : £%.2f\n', profit);
        fprintf('  Throughput        : %.2f MWh\n\n', throughput);
        
        fprintf('[Carbon Emissions]\n');
        fprintf('  Gross Emissions   : +%.2f kg\n', gross_emissions);
        fprintf('  Net Grid Impact   :  %.2f kg\n', net_emissions);
        if net_emissions < 0
            fprintf('    -> Negative net emissions: Arbitrage naturally shifts carbon (charges at low price/carbon, discharges at high price/carbon).\n');
        end
        
        fprintf('\n[Physical Validation]\n');
        % Energy balance validation
        E_calc    = zeros(T,1);
        E_calc(1) = E0 + (P_ch(1)*eta_ch - P_dis(1)/eta_dis)*dt;
        for t = 2:T
            E_calc(t) = E_calc(t-1) + (P_ch(t)*eta_ch - P_dis(t)/eta_dis)*dt;
        end
        max_err = max(abs(E - E_calc));
        
        fprintf('  Energy balance err : %g MWh -> ', max_err);
        if max_err < 1e-6, fprintf('[PASS]\n'); else, fprintf('[FAIL]\n'); end
        
        % Power bounds validation
        fprintf('  Power bounds       : Ch max %.4f MW, Dis max %.4f MW -> ', max(P_ch), max(P_dis));
        if max(P_ch) <= P_max+1e-4 && max(P_dis) <= P_max+1e-4, fprintf('[PASS]\n'); end
        
        % SOC bounds validation
        fprintf('  SOC bounds         : Max %.4f MWh, Min %.4f MWh -> ', max(E), min(E));
        if max(E) <= E_max+1e-4 && min(E) >= -1e-4, fprintf('[PASS]\n'); end
        
        % Final SOC validation
        fprintf('  Final SOC          : %.4f MWh (req >= %.2f MWh) -> ', E(end), E0);
        if E(end) >= E0-1e-6, fprintf('[PASS]\n'); end
        fprintf('======================================================\n');
        
        % Store base case trajectory for plotting
        E_base     = E;
        P_ch_base  = P_ch;
        P_dis_base = P_dis;
        P_net_base = P_dis - P_ch;
    end
end


%  Stage 6: Results Table

base_gross = results_gross_emissions(1);

fprintf('\n[Carbon-aware Dispatch Results Table]\n');
fprintf('---------------------------------------------------------------------------------------------\n');
fprintf('%-12s | %-12s | %-18s | %-18s | %-14s | %-10s\n', ...
    'Lambda(£/kg)', 'Profit(£)', 'Gross Emission(kg)', 'Net Impact(kg)', 'Throughput(MWh)', 'Reduction(%)');
fprintf('---------------------------------------------------------------------------------------------\n');

for i = 1:num_cases
    if i == 1
        red_pct = 0.0;
    else
        red_pct = (base_gross - results_gross_emissions(i)) / base_gross * 100;
    end
    fprintf('%-12.2f | %-12.2f | %-18.2f | %-18.2f | %-14.2f | %-10.2f%%\n', ...
        lambda_values(i), results_profit(i), ...
        results_gross_emissions(i), results_net_emissions(i), ...
        results_throughput(i), red_pct);
end
fprintf('---------------------------------------------------------------------------------------------\n\n');


%  Stage 7: Visualization

red_pct_arr = (base_gross - results_gross_emissions) / base_gross * 100;
profit_loss  = results_profit(1) - results_profit;


% Figure 1: Pareto Front

figure('Position', [150, 150, 780, 560], 'Name', 'Pareto Front');
plot(results_gross_emissions/1000, results_profit/1000, '-o', ...
    'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', [0.8500 0.3250 0.0980]);
grid on; hold on;
xlabel('Gross Charging Emissions (t CO_2)', 'FontWeight', 'bold', 'FontSize', 11);
ylabel('Total Arbitrage Profit (k£)', 'FontWeight', 'bold', 'FontSize', 11);
title('Carbon-aware Dispatch: Profit vs Emission Pareto Front', 'FontSize', 11);

y_range  = max(results_profit/1000) - min(results_profit/1000);
y_offset = y_range * 0.03;

for i = 1:num_cases
    text(results_gross_emissions(i)/1000, results_profit(i)/1000 + y_offset, ...
        sprintf('λ=%g', lambda_values(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
end

% Mark Knee Point
grad = diff(results_profit) ./ diff(results_gross_emissions);
[~, knee_idx] = max(abs(grad));
text(results_gross_emissions(knee_idx+1)/1000, ...
    results_profit(knee_idx+1)/1000 - y_offset*2, ...
    '<- Knee Point', 'Color', [0 0 0.8], 'FontSize', 10);
hold off;


% Figure 2: Trade-off Dual Axis

figure('Position', [200, 200, 780, 500], 'Name', 'Emission Reduction vs Profit Loss');
yyaxis left;
plot(lambda_values, red_pct_arr, '-s', 'LineWidth', 2, ...
    'MarkerSize', 8, 'MarkerFaceColor', [0.47 0.67 0.19]);
ylabel('Charging Emission Reduction (%)', 'FontSize', 10);
ylim([0, min(100, max(red_pct_arr)*1.2 + 2)]);

yyaxis right;
plot(lambda_values, profit_loss/1000, '-^', 'LineWidth', 2, ...
    'MarkerSize', 8, 'MarkerFaceColor', [0.85 0.33 0.10]);
ylabel('Profit Loss vs Base Case (k£)', 'FontSize', 10);

xlabel('Carbon Penalty Lambda (£/kg)', 'FontSize', 11);
title('Trade-off: Emission Reduction vs Profit Loss', 'FontSize', 11);
grid on;
legend({'Reduction (%)', 'Profit Loss (k£)'}, 'Location', 'northwest', 'FontSize', 10);

% Figure 3: Base Case Time Series (First 7 days)

T_plot = min(168, T);
figure('Position', [100, 100, 1050, 750], 'Name', 'Base Case Dispatch (lambda=0)');

% Subplot A: Market Signals
subplot(4,1,1);
yyaxis left;
plot(1:T_plot, price_gbp_mwh(1:T_plot), 'k-', 'LineWidth', 1.2);
ylabel('Price (£/MWh)', 'FontSize', 9);
title('Day-ahead Price and Carbon Intensity (lambda=0, First 168 hours)', 'FontSize', 10);
yyaxis right;
plot(1:T_plot, carbon_kg_mwh(1:T_plot), 'r--', 'LineWidth', 1.2);
ylabel('Carbon Intensity (kg/MWh)', 'FontSize', 9);
xlim([1 T_plot]); grid on;

% Subplot B: SOC Trajectory
subplot(4,1,2);
plot(1:T_plot, E_base(1:T_plot), 'b-', 'LineWidth', 1.8);
ylabel('SOC (MWh)', 'FontSize', 9);
title('Battery SOC Trajectory (lambda=0)', 'FontSize', 10);
ylim([0 2.35]); xlim([1 T_plot]);
yline(E0,    'k--', 'Initial/Final Bound 1 MWh', 'LabelHorizontalAlignment', 'left');
yline(E_max, 'r:',  'E_{max}=2 MWh',       'LabelHorizontalAlignment', 'left');
grid on;

% Subplot C: Net Power Dispatch
subplot(4,1,3);
bar_h = bar(1:T_plot, P_net_base(1:T_plot), 'EdgeColor', 'none');
bar_h.FaceColor = 'flat';
for t = 1:T_plot
    if P_net_base(t) >= 0
        bar_h.CData(t,:) = [0.17 0.51 0.34]; % Discharge - Green
    else
        bar_h.CData(t,:) = [0.75 0.22 0.17]; % Charge - Red
    end
end
ylabel('Net Power (MW)', 'FontSize', 9);
title('Battery Dispatch Commands (Green=Discharge, Red=Charge, lambda=0)', 'FontSize', 10);
ylim([-1.15 1.15]); xlim([0.5 T_plot+0.5]); grid on;

% Subplot D: Hourly Charging Carbon Emissions
subplot(4,1,4);
bar(1:T_plot, P_ch_base(1:T_plot) .* carbon_kg_mwh(1:T_plot), ...
    'FaceColor', [0.85 0.33 0.10], 'EdgeColor', 'none');
ylabel('Emissions (kg/h)', 'FontSize', 9);
title('Hourly Charging Carbon Emissions (lambda=0)', 'FontSize', 10);
xlim([0.5 T_plot+0.5]);
xlabel('Time (hours)', 'FontSize', 10);
grid on;

drawnow;
fprintf('[Visualization Complete] Generated 3 figures:\n');
fprintf('  Fig 1: Pareto Front (Profit vs Gross Emissions)\n');
fprintf('  Fig 2: Trade-off Dual Axis (Reduction & Profit Loss vs Lambda)\n');
fprintf('  Fig 3: Base Case Time Series (4 subplots)\n');
fprintf('======================================================\n');
