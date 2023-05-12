clear; clc; close all;
addpath('../', "burgers-helpers/");

%% Problem set-up
N       = 2^7+1;                  % num grid points
dt      = 1e-4;                   % timestep
T_end   = 1;                      % final time
K       = T_end/dt;               % num time steps
tspan = linspace(0.0,T_end,K+1);  % time span
sspan = linspace(0,1.0,N);        % spatial span

mu = 0.3;               % diffusion coefficient

type = 2;
% run FOM with input 1s to get reference trajectory
if type == 1
    u_ref = ones(K,1);
    IC = zeros(N,1);
else
    u_ref = zeros(K,1);
    IC = sin(pi * linspace(0,1,N))';
end

[A, B, F] = getBurgers_ABF_Matrices(N,1/(N-1),dt,mu);
H = F2Hs(F);
s_ref = semiImplicitEuler(A, F, B, dt, u_ref, IC);

%% Surface Plot for verification
figure(1);
s = surf(linspace(0.0,T_end,K+1),linspace(0.0,1.0,N),s_ref,'FaceAlpha',0.8,DisplayName="\mu="+num2str(mu));
s.EdgeColor = 'none';
xlabel("t, time");
ylabel("\omega, space");
zlabel("x(\omega,t), velocity")
axis tight
view(-73.25,38.649)
grid on
text(0.1,0.8,1,"\mu = "+num2str(mu),'FontSize',14);

%% Slice of surface plot (time)
figure(2);
plot(0,0,MarkerSize=0.01,HandleVisibility="off")
hold on; grid on; grid minor; box on;
cmap = jet(length(1:floor(K/10):K+1));
ct = 1;
for i = 1:floor(K/10):K+1
    plot(sspan,s_ref(:,i),Color=cmap(ct,:),DisplayName="$t="+num2str(i)+"$");
    ct = ct + 1;
end
hold off; legend(Interpreter="latex");
xlabel("\omega, space")
ylabel("x, velocity")
title("Burgers' plot sliced by time \mu="+num2str(mu))

%% Slice of surface plot (space)
figure(3);
plot(0,0,MarkerSize=0.01,HandleVisibility="off")
hold on; grid on; grid minor; box on;
cmap = jet(length(1:floor(N/10):N+1));
ct = 1;
for i = 1:floor(N/10):N+1
    plot(tspan,s_ref(i,:),Color=cmap(ct,:),DisplayName="$x="+num2str(i)+"$");
    ct = ct + 1;
end
hold off; legend(Interpreter="latex");
xlabel("t, time")
ylabel("x, velocity")
title("Burgers' plot sliced by space \mu="+num2str(mu))

%% Plot the Energy
figure(4);
plot(tspan, vecnorm(s_ref).^2/2)
xlabel("t, time")
ylabel("Energy")
grid on; grid minor; box on;
title("Energy over time of Burgers' Equation")

%% Check the Constraint Residual (H)
CR_h = constraintResidual_H(H);

%% Check the Constraint Residual (F)
CR_f = constraintResidual_F(F);

%% Plot the Energy Rates
QER_h = quadEnergyRate(H, s_ref);
QER_f = quadEnergyRate(F, s_ref);
LER = linEnergyRate(A, s_ref);
CER = controlEnergyRate(B, s_ref, u_ref);

fig5 = figure(5);
fig5.Position = [500 500 1500 480];
t = tiledlayout(1,3,"TileSpacing","compact","Padding","compact");
nexttile;
    plot(tspan, QER_h, DisplayName="H", LineWidth=4, Color="b")
    hold on; grid on; grid minor; box on;
    plot(tspan, QER_f, DisplayName="F", LineStyle="--", LineWidth=2, Color="g")
    hold off; legend(Location="best");
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Quadratic Energy Rate")
nexttile;
    plot(tspan, LER, Color="r", LineStyle=":", LineWidth=2, DisplayName="A")
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Linear Energy Rate")
    grid on; grid minor; box on; legend(Location="best")
nexttile;
    plot(tspan, CER, Color="k", LineStyle="-.", LineWidth=2, DisplayName="B")
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Control Energy Rate")
    grid on; grid minor; box on; legend(Location="best")

figure(6);
TER = QER_h+LER+CER;
semilogy(tspan, TER, Color="b", LineWidth=2)
xlabel("t, time")
ylabel("Energy Rate")
title("Total Energy Rate")
grid on; grid minor; box on;


%% collect data for a series of trajectories with random inputs
num_inputs = 10;
if type == 1
    U_rand = rand(K,num_inputs);
else
    U_rand = 0.2*rand(K,num_inputs)-0.1;
end
x_all = cell(num_inputs,1);
xdot_all = cell(num_inputs,1);
for i = 1:num_inputs
    s_rand = semiImplicitEuler(A, F, B, dt, U_rand(:,i), IC);
    x_all{i}    = s_rand(:,2:end);
    xdot_all{i} = (s_rand(:,2:end)-s_rand(:,1:end-1))/dt;
end

X = cat(2,x_all{:});        % concatenate data from random trajectories
R = cat(2,xdot_all{:});    
U = reshape(U_rand(:,1:num_inputs),K*num_inputs,1);

[U_svd,s_svd,~] = svd(X,'econ'); % take SVD for POD basis

%% Operator inference parameters
params.modelform = 'LQI';           % model is linear-quadratic with input term
params.modeltime = 'continuous';    % learn time-continuous model
params.dt        = dt;              % timestep to compute state time deriv
params.ddt_order = '1ex';           % explicit 1st order timestep scheme

%% for different basis sizes r, compute basis, learn model, and calculate state error 
r_vals = 1:20;
err_inf = zeros(length(r_vals),1);  % relative state error for inferred model
err_int = zeros(length(r_vals),1);  % for intrusive model

% intrusive
rmax = max(r_vals);
Vr = U_svd(:,1:rmax);
Aint = Vr' * A * Vr;
Bint = Vr' * B;
Ln = elimat(N); Dr = dupmat(max(r_vals));
Fint = Vr' * F * Ln * kron(Vr,Vr) * Dr;
Hint = F2Hs(Fint);

% op-inf (with stability check)
while true
    [operators] = inferOperators(X, U, Vr, params, R);
    Ahat = operators.A;
    Fhat = operators.F;
    Bhat = operators.B;
    
    % Check if the inferred operator is stable 
    lambda = eig(Ahat);
    Re_lambda = real(lambda);
    if all(Re_lambda(:) < 0)
        break;
    else
        warning("For mu = %f, order of r = %d is unstable. Decrementing max order.\n", mu, rmax);
        rmax = rmax - 1;
        Vr = U_svd(:,1:rmax);
    end
end

for j = 1:rmax
    r = r_vals(j);
    Vr = U_svd(:,1:r);

    Fhat_extract = extractF(Fhat, r);
    s_hat = semiImplicitEuler(Ahat(1:r,1:r),Fhat_extract,Bhat(1:r,:),dt,u_ref,Vr'*IC);
    s_rec = Vr*s_hat;
    err_inf(j) = norm(s_rec-s_ref,'fro')/norm(s_ref,'fro');
    
    Fint_extract = extractF(Fint, r);
    s_int = semiImplicitEuler(Aint(1:r,1:r),Fint_extract,Bint(1:r,:),dt,u_ref,Vr'*IC);
    s_tmp = Vr*s_int;
    err_int(j) = norm(s_tmp-s_ref,'fro')/norm(s_ref,'fro');
end

%% Plotting
figure(7); clf
semilogy(r_vals(1:rmax),err_inf(1:rmax), DisplayName="opinf"); grid on; grid minor; hold on;
semilogy(r_vals(1:rmax),err_int(1:rmax), DisplayName="int"); 
hold off; legend(Location="southwest");
xlabel('Model size $r$','Interpreter','LaTeX')
ylabel('Relative state reconstruction error','Interpreter','LaTeX')
title("Burgers inferred model error, $\mu$ = "+num2str(mu),'Interpreter','LaTeX')

%% Check the Constraint Residual for intrusive (H)
CR_h = constraintResidual_H(operators.H);

%% Check the Constraint Residual for intrusive (F)
CR_f = constraintResidual_F(operators.F);

%% Plot the Energy Rates
QER_h = quadEnergyRate(operators.H, U_svd(:,1:rmax)' * s_ref);
QER_f = quadEnergyRate(operators.F, U_svd(:,1:rmax)' * s_ref);
LER = linEnergyRate(operators.A, U_svd(:,1:rmax)' * s_ref);
CER = controlEnergyRate(operators.B, U_svd(:,1:rmax)' * s_ref, u_ref);

fig8 = figure(8);
fig8.Position = [500 500 1500 480];
t = tiledlayout(1,3,"TileSpacing","compact","Padding","compact");
nexttile;
    plot(tspan, QER_h, DisplayName="H", LineWidth=4, Color="b")
    hold on; grid on; grid minor; box on;
    plot(tspan, QER_f, DisplayName="F", LineStyle="--", LineWidth=2, Color="g")
    hold off; legend(Location="best");
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Quadratic Energy Rate")
nexttile;
    plot(tspan, LER, Color="r", LineStyle=":", LineWidth=2, DisplayName="A")
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Linear Energy Rate")
    grid on; grid minor; box on; legend(Location="best")
nexttile;
    plot(tspan, CER, Color="k", LineStyle="-.", LineWidth=2, DisplayName="B")
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Control Energy Rate")
    grid on; grid minor; box on; legend(Location="best")

figure(9);
TER = QER_h+LER+CER;
semilogy(tspan, TER, Color="b", LineWidth=2)
xlabel("t, time")
ylabel("Energy Rate")
title("Total Energy Rate")
grid on; grid minor; box on;


%% Check the Constraint Residual for intrusive (H)
CR_h = constraintResidual_H(Hint);

%% Check the Constraint Residual for intrusive (F)
CR_f = constraintResidual_F(Fint);

%% Plot the Energy Rates
rmax = max(r_vals);
QER_h = quadEnergyRate(Hint, U_svd(:,1:rmax)' * s_ref);
QER_f = quadEnergyRate(Fint, U_svd(:,1:rmax)' * s_ref);
LER = linEnergyRate(Aint, U_svd(:,1:rmax)' * s_ref);
CER = controlEnergyRate(Bint, U_svd(:,1:rmax)' * s_ref, u_ref);

fig10 = figure(10);
fig10.Position = [500 500 1500 480];
t = tiledlayout(1,3,"TileSpacing","compact","Padding","compact");
nexttile;
    plot(tspan, QER_h, DisplayName="H", LineWidth=4, Color="b")
    hold on; grid on; grid minor; box on;
    plot(tspan, QER_f, DisplayName="F", LineStyle="--", LineWidth=2, Color="g")
    hold off; legend(Location="best");
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Quadratic Energy Rate")
nexttile;
    plot(tspan, LER, Color="r", LineStyle=":", LineWidth=2, DisplayName="A")
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Linear Energy Rate")
    grid on; grid minor; box on; legend(Location="best")
nexttile;
    plot(tspan, CER, Color="k", LineStyle="-.", LineWidth=2, DisplayName="B")
    xlabel("t, time")
    ylabel("Energy Rate")
    title("Control Energy Rate")
    grid on; grid minor; box on; legend(Location="best")

figure(11);
TER = QER_h+LER+CER;
semilogy(tspan, TER, Color="b", LineWidth=2)
xlabel("t, time")
ylabel("Energy Rate")
title("Total Energy Rate")
grid on; grid minor; box on;

