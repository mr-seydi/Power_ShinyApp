#TWT function
source("TWT2.R")
#SnPM function
source("Fmax.R")
#IWT function
source("IWT.R")

#path for vgrf_mean_data
path <- "vgrf_fig2.txt"


#############Loading Library#####################
library(fda)
#library(fdatest)
#install.packages("reticulate")
library(reticulate) # to read python code
#pip install spm1d
spm1d <- reticulate::import("spm1d")
numpy <- reticulate::import("numpy")
#pip install power1d
power1d <- reticulate::import("power1d")

scipy.ndimage <- reticulate::import("scipy.ndimage")

################Data with NA#########################
completed_data <- function(x, y, defined_domain=c(0,100)) {
  
  if (length(defined_domain) != 2) {
    stop("Domain must have a form like c(starting point,ending point)")
  }
  start_domain <- defined_domain[1]
  end_domain <- defined_domain[2]

  # Perform linear interpolation using approx() function
  xnew <- seq(start_domain, end_domain, by = 1)  # New x values with steps of 1
  interpolated <- approx(na.omit(x), na.omit(y), xout = xnew)  # Interpolate y values
  
  # Return new y values
  return(interpolated$y)
}


###################Functions###########################

sigma_to_fwhm <- function(sigma){
  return(sigma*(2 * sqrt(2 * log(2))))
}

fwhm_to_sigma <- function(fwhm){
  return(fwhm / (2 * sqrt(2 * log(2))))
}

#Normal kernel smoothing function
# ksmooth_gaussian <- function(x, fwhm) { 
#   sigma <- fwhm_to_sigma(fwhm)
#   x_vals <- 1:length(x)
#   smoothed_vals <- numeric(length = length(x))
#   
#   
#   for (x_position in x_vals) {
#     kernel <- exp(-((x_vals - x_position)^2) / (2 * sigma^2))
#     #kernel <- exp(-((x_vals - x_position)^2) / (2 * sigma^2))/sqrt(2*pi*sigma^2)
#     #Results for both Kernels are the same
#     kernel <- kernel / sum(kernel)
#     smoothed_vals[x_position] <- sum(x * kernel)
#   }
#   
#   return(smoothed_vals)
# }
ksmooth_gaussian <- function(x, fwhm) {
  
  SD = fwhm_to_sigma(fwhm)
  #smoothed_vals = ksmooth(x = 1:length(x), y = x, bandwidth = SD, kernel = "normal")$y
  smoothed_vals = scipy.ndimage$gaussian_filter1d(x, SD, mode='wrap')#$tolist()
}


#unsmoothed guassian noise curve
noise_guassian_curve <- function(number_of_curves, continuum_size){ 
  data <- matrix(rnorm(number_of_curves*continuum_size),
                       nrow = number_of_curves, ncol = continuum_size)
  return(data)
  
}


#smoothed gussian noise curves
smoothed_gussian_curves <- function(data, mu, sig, fwhm){
  smoothed_data <- apply(data, 1, FUN = function(x) ksmooth_gaussian(x,fwhm))
  standard_smoothed_data=apply(smoothed_data, 2, scale)
  trans_data=apply(standard_smoothed_data, 2, FUN = function(x){(mu+x*sig)})
  return(trans_data) #dim(output)=continuum_size*number_of_curves
}

# Generating data (Baseline+noise+signal) or (Baseline+noise) or (Baseline+signal)
data_generator <- function(data,signal,noise) {
  sample_size <- dim(noise)[2]
  data_baseline <- matrix(rep(data,time=sample_size),
                          ncol = sample_size)
  if (missing(signal)) {
    data_out <- data_baseline + noise
  } else if (missing(noise)) {
    signal_baseline <- matrix(rep(signal,time=sample_size),
                              ncol = sample_size)
    data_out <- data_baseline + signal_baseline
  } else {
    signal_baseline <- matrix(rep(signal,time=sample_size),
                              ncol = sample_size)
    data_out <- data_baseline + signal_baseline + noise 
  }
  return(data_out)
}



gaussian_pulse <- function(center, fwhm, continuum_size) {
  sigma = fwhm_to_sigma(fwhm)
  x_values = seq(0, continuum_size-1, by = 1)
  dens <- dnorm(x_values, mean = center, sd = sigma)
  return(list(density_val=dens, x_values=x_values))
}

amplitude_pulse <- function(data, amp){
  scaling_factor = amp / max(data)
  y_values = scaling_factor * data
  return(y_values)
}


##############Methods functions###########

Initialize_method_list <- function(Methods, Conti_size=101, Iter_number=100){
  method_list <- list()
  for (M in Methods) {
    method_list[[M]] <- matrix(,nrow = Conti_size, ncol = 0)
  }
  return(method_list)
}

Power_data_generator <- function(Sample_size, Data,
                                 Signal, Conti_size = 101,
                                 Noise_mu, Noise_sig, Noise_fwhm){
  
  noise1 <- noise_guassian_curve(number_of_curves = Sample_size,
                                 continuum_size = Conti_size)
  noise2 <- noise_guassian_curve(number_of_curves = Sample_size,
                                 continuum_size = Conti_size)
  noise1 <- smoothed_gussian_curves(noise1, Noise_mu, Noise_sig, Noise_fwhm)
  noise2 <- smoothed_gussian_curves(noise2, Noise_mu, Noise_sig, Noise_fwhm)
  
  if (is.null(Signal)) {
    data1 <- data_generator(data = Data[,1], noise = noise1)
    data2 <- data_generator(data = Data[,2], noise = noise2)
  } else {
    data1 <- data_generator(data = Data, signal = Signal, noise = noise1)
    data2 <- data_generator(data = Data, noise = noise2)      
  }
  
  return(list(data1 = data1, data2 = data2))
}

Pvalue_calculator <- function(method_list, data1, data2){
  
  Methods <- names(method_list)
  
  for (M in Methods) {
    Pvalues <- Pval_method(sampel1 = t(data1), sample2 = t(data2),
                           method = M)
    #p_values dimension is continuum_size*Iter_number
    method_list[[M]] <- cbind(method_list[[M]], Pvalues)
  }
  return(method_list) #Filled in method list
}


Power_calculator <- function(Pvalues, Iter_number, Alpha){
  
  Methods <- names(Pvalues)
  
  for (M in Methods) {
    pvalue_less_alpha <- Pvalues[[M]] < Alpha
    power <- sum(colSums(pvalue_less_alpha) > 0) / Iter_number
    Pvalues[[M]] <- power
  }
  
  return(Pvalues)
  
}

# 
# Power_calculator <- function(Methods ,Sample_size, Iter_number, Data,
#                              Signal, Conti_size,
#                              Noise_mu, Noise_sig, Noise_fwhm, Alpha){
#   
#   power_list <- list()
#   
#   for (M in Methods) {
#     p_values <- matrix(NA,nrow = Conti_size, ncol = Iter_number)
#     power_list[[M]] <- p_values
#   }
#   
#   # Progress indicator for the iteration loop
#   withProgress(message = 'Calculating Power...', value = 0, {
#   
#   for (i in 1:Iter_number) {
#     
#     
#     # Increment the progress bar with each iteration
#     incProgress(1 / Iter_number, detail = paste("Iteration", i, "of",
#                                                 Iter_number))
#     
#     
#     noise1 <- noise_guassian_curve(number_of_curves = Sample_size,
#                                    continuum_size = Conti_size)
#     noise2 <- noise_guassian_curve(number_of_curves = Sample_size,
#                                    continuum_size = Conti_size)
#     noise1 <- smoothed_gussian_curves(noise1, Noise_mu, Noise_sig, Noise_fwhm)
#     noise2 <- smoothed_gussian_curves(noise2, Noise_mu, Noise_sig, Noise_fwhm)
#     
#     if (missing(Signal)) {
#       data1 <- data_generator(data = Data[,1], noise = noise1)
#       data2 <- data_generator(data = Data[,2], noise = noise2)
#     } else {
#       data1 <- data_generator(data = Data, signal = Signal, noise = noise1)
#       data2 <- data_generator(data = Data, noise = noise2)      
#     }
#     
# 
#     for (M in Methods) {
#       power_list[[M]][,i] <- Pval_method(sampel1 = t(data1), sample2 = t(data2),
#                                           method = M) #p_values dimension is continuum_size*Iter_number
#     }
#   }
#     
#   }) # Closing withProgress block here
#   
#     
#   # After all iterations, calculate the final power for each method  
#   for (M in Methods) {
#     pvalue_less_alpha=power_list[[M]]<Alpha
#     power=sum(colSums(pvalue_less_alpha)>0)/Iter_number
#     power_list[[M]] <- power
#   }
#   
#   return(power_list)
# }
# 

Pval_method <- function(sampel1,sample2,method) {
  if (method=="IWT") {
    pval <- IWT(sampel1,sample2)
  } else if (method=="TWT"){
    pval <- TWT(sampel1,sample2)
  } else if (method=="Parametric_SPM"){
    pval <- p_spm(sampel1,sample2)
  } else if (method=="Nonparametric_SPM"){
    pval <- p_snpm(sampel1,sample2)
  } else {
    stop("Choose a method between options")
  }
  return(pval)
}

IWT <- function(data1,data2){
  IWT2=IWT2(data1, data2)
  pvalue_adj_IWT2=IWT2$adjusted_pval
  return(pvalue_adj_IWT2)
}

TWT <- function(data1,data2){
  TWT2=TWT2_new(data1,data2)
  pvalue_adj_TWT2=TWT2$adjusted_pval
  return(pvalue_adj_TWT2)
}

p_spm <- function(data1, data2){
  spm  <- spm1d$stats$ttest2(data1, data2, equal_var=FALSE)
  p_val <- spm1d$rft1d$f$sf((spm$z)^2, spm$df, spm$Q, spm$fwhm, withBonf=TRUE)
  return(p_val)
}

p_snpm <- function(data1, data2, B = 1000){
  
  n1 = dim(data1)[1]
  n2 = dim(data2)[1]
  
  
  group12 = factor(c(rep(1,n1),rep(2,n2)))
  data_group12 <- rbind(data1,data2)
  
  # Create a data frame that includes both data_group12 and group12
  combined_data <- data.frame(data_group12, group12)
  
  # Pass the formula with the combined data to Fmax
  Fmax_pval <- Fmax(data_group12 ~ group12, DATA = combined_data)
  return(Fmax_pval$adjusted_pval_F)
  
} 
  


#######Python noise and pulse##############

SmoothGaussian_noise <- function(sample_size, continuum_size, mu, sigma, fwhm){
  noise   <- power1d$noise$SmoothGaussian( J=as.integer(sample_size), 
                                           Q=as.integer(continuum_size), mu=mu,
                                           sigma=sigma, fwhm=fwhm, pad=FALSE)$value
  #dim(output)=sample_size*continuum_size
  return(noise)
}
GaussianPulse <- function(continuum_size, pulse_center, fwhm, amplitude){
  pulse <- power1d$geom$GaussianPulse( Q=as.integer(continuum_size), q=as.integer(pulse_center),
                              fwhm=fwhm, amp=amplitude )$value
  return(pulse)
}


############Cancel button####################
# Function to read the status from a file
get_status <- function(status_file){
  scan(status_file, what = "character",sep="\n")
}
# Function to write the status to a file
set_status <- function(msg, status_file){
  write(msg, status_file)
}
# Function to set the status to "interrupt"
fire_interrupt <- function(status_file){
  set_status("interrupt",status_file)
}

interrupted <- function(status_file){
  get_status(status_file) == "interrupt"
}

############## Parallel processing functions ####################
# Custom combine function to accumulate matrices across iterations
parallel_combine_function <- function(x, y) {
  for (M in names(x)) {
    # Combine matrices from the same method in both x and y
    x[[M]] <- cbind(x[[M]], y[[M]])
  }
  return(x)
}
  