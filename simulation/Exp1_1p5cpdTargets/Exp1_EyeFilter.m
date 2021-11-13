%% timing
datestr(now)
start_time = clock;

%% simulation
simulation_name = mfilename;

%% load a prepared experiment (after manual cd)
% subject = '';
% load(['Experiment_', subject, '_patched.mat']);
% load(['Stimulus', subject, '_patched.mat']);

%% choose targets
targets = Experiment.conditionLabels;
tar_size = Stimulus.sideLength;
rc = Stimulus.targets(:,:,1) * Stimulus.bgMean;
sine = Stimulus.targets(:,:,2) * Stimulus.bgMean;
tri = Stimulus.targets(:,:,3) * Stimulus.bgMean;
sqr = Stimulus.targets(:,:,4) * Stimulus.bgMean;
rect = Stimulus.targets(:,:,5) * Stimulus.bgMean;

%% choose backgrounds
groups = ["images", "controls"];
n_background = 2000;
background_lumi = Stimulus.bgMean;
background_std = Stimulus.bgContrast * Stimulus.bgMean;
sqrt_contrast_m = Stimulus.sqrtContrast_m;
controls = zeros(tar_size,tar_size,n_background,2);
images = zeros(tar_size,tar_size,n_background,2);
line_sigmas = zeros(length(groups),2,tar_size);

%% choose TM methods
TMs = ["direct_template_matching", "eye_template_matching",...
    "norm_template_matching", "norm_eye_template_matching"];
TMs_short = ["TM", "ETM","RTM", "ERTM"];
diameter = 4; % pupil size
w = 550; %wavelength

%% iteration
%data to save
d_t = 1;
max_err = 1e-5;
max_iter = 20;

%% result boxes
amp_all = zeros(length(targets),length(groups),length(TMs),max_iter);
amp_all(:,:,:,1) = 0.01; % initial amplitude
d_all = zeros(length(targets),length(groups),length(TMs),2,max_iter);
threshold=zeros(length(groups)*length(TMs),length(targets));

%% generate backgrounds
controls(:,:,:,1) = create_power_noise_sample_field(tar_size, tar_size, Stimulus.scenePx, Stimulus.scenePx,...
    n_background, 1, background_lumi, background_std) / Stimulus.backgroundStd;
controls(:,:,:,2) = create_power_noise_sample_field(tar_size, tar_size, Stimulus.scenePx, Stimulus.scenePx,...
    n_background, 1, background_lumi, background_std) / Stimulus.backgroundStd;
for i=1:n_background          
    images(:,:,i,1) = contrast_modulate(controls(:,:,i,1),sqrt_contrast_m);
    images(:,:,i,2) = contrast_modulate(controls(:,:,i,2),sqrt_contrast_m); 
end

controls = round(controls);
controls(controls < 0) = 0;
controls(controls > 2^Experiment.monitorBit-1) = 2^Experiment.monitorBit-1;

images = round(images);
images(images < 0) = 0;
images(images > 2^Experiment.monitorBit-1) = 2^Experiment.monitorBit-1;

r_power = 1;

%% detectability computation
for T=1:length(targets)
    target = targets(T);
    for G=1:length(groups)
        for M=1:length(TMs)
           for I=1:max_iter
               eval('amp_'+target+'=amp_all(T,G,M,I)*'+target+';');
               if M==1
                   appendix = '';
                   [r1,~,sigmas] = eval(TMs(M)+'(amp_'+target+','+groups(G)+',0'+appendix+');');
                   line_sigmas(G,1,:)= sigmas;
               elseif M==2
                   appendix = ',diameter,w';
                   [r3,~,sigmas_w] = eval(TMs(M)+'(amp_'+target+','+groups(G)+',0'+appendix+');');
                   line_sigmas(G,2,:)= sigmas_w;
               elseif M==3
                   appendix = ',''dichotomy'',sigmas';
                   r1 = eval(TMs(M)+'(amp_'+target+','+groups(G)+',0'+appendix+');');
               elseif M==4
                   appendix = ',''dichotomy'',sigmas_w,diameter,w';
                   r3 = eval(TMs(M)+'(amp_'+target+','+groups(G)+',0'+appendix+');');
               end

               if M == 2 || M == 4
                    r4 = eval(TMs(M)+'(amp_'+target+','+groups(G)+',1'+appendix+');');
                    mu_1 = [mean(r1); mean(r3)]; mu_2 = [mean(r2); mean(r4)];
                    d = classify_normals([mu_1,cov(r1,r3)],[mu_2,cov(r2,r4)], 'plotmode', false).norm_dprime;
                    d_all(T,G,M,2,I) = sqrt((var(r1)^2+var(r3)^2+var(r2)^2+var(r4)^2)/2);
               else
                   r2 = eval(TMs(M)+'(amp_'+target+','+groups(G)+',1'+appendix+');');
                   [d, d_all(T,G,M,2,I)] = dprime(r1,r2);
               end

               d_all(T,G,M,1,I) = d;                
               if I < max_iter
                   if mod(I,2)
                       amp_all(T,G,M,I+1) = amp_all(T,G,M,I) * d_t / d;
                   else
                       amp_all(T,G,M,I+1) = 0.5*amp_all(T,G,M,I)*(1 + d_t / d);
                   end
               end
               eval('amp_'+target+'=amp_all(T,G,M,I+1)*'+target+';');

               if abs(d-d_t) <= max_err
                    break;
               end

               if M == 2
                   appendix = '';
                   r1 = eval(TMs(M-1)+'(amp_'+target+','+groups(G)+',0'+appendix+');');
                   r2 = eval(TMs(M-1)+'(amp_'+target+','+groups(G)+',1'+appendix+');');
               elseif M == 4
                   appendix = ',''dichotomy'',sigmas';
                   r1 = eval(TMs(M-1)+'(amp_'+target+','+groups(G)+',0'+appendix+');');
                   r2 = eval(TMs(M-1)+'(amp_'+target+','+groups(G)+',1'+appendix+');');
               end
           end
           threshold(length(TMs)*(G-1)+M,T) = amp_all(T,G,M,I+1);
        end
    end
end

%% save results
save([simulation_name,'.mat'],'amp_all', 'd_all', 'threshold','r_power', 'line_sigmas');

%% end timing and display in hours
datestr(now)
end_time = clock;
etime(end_time, start_time) / 3600.0

%% plot results
load([simulation_name,'.mat']);
db_threshold_plot(mag2db(threshold),groups,TMs_short,targets,...
    simulation_name);
