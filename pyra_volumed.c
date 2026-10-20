// pyra volumed
// reads volumewheel value and applies it to the mixer
// temporary daemon, should be made part of the input daemon
//
// The wheel is a tapered potentiometer, not a linear one, and the control it
// drives is already in dB (Handsfree Playback Volume, 0..29 = -52..+6 dB in
// 2 dB steps). Mapping the raw reading linearly onto the control stacked the
// two curves: on the unit this was measured on, the lower half of the wheel
// covered -52..-42 dB and was silent, and the upper half the other 48 dB.
//
// So the reading is turned back into wheel travel through calibration points
// taken at quarter turns, interpolating in log(raw) between them, and travel
// is spread evenly over step_lo..step_hi. Both can be overridden for a unit
// whose pot reads differently, in /etc/pyra_volumed.conf:
//
//     # raw readings at 0, 1/4, 1/2, 3/4 and full travel
//     cal 16 144 394 1071 2068
//     # control steps the wheel spans (6 = -40 dB, 29 = +6 dB)
//     range 6 29
//
// Read a calibration point by holding the wheel still and reading
// /sys/bus/iio/devices/iio:deviceN/in_voltage2_raw (the N whose name is
// palmas-gpadc).


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <alsa/asoundlib.h>
#include <unistd.h>
#include <iio.h>


#define DEVNAME "palmas-gpadc"
#define CHANNEL "voltage2"

#define CARD "hw:CARD=L15"

#define SELEM "Handsfree"

#define MIN_DELAY 100000
#define MAX_DELAY 1000000

#define CONFIG "/etc/pyra_volumed.conf"
#define NCAL 5

// measured on one unit, 2026-10-20
static double cal[NCAL]={16,144,394,1071,2068};
static long step_lo=6, step_hi=29;

// readings this close to the bottom are "all the way down": volume 0
#define RAW_OFF (cal[0]*1.25)

// the log mapping magnifies ADC noise at the bottom of the travel, so only
// move once the wheel is this far past the edge of the current step
#define HYSTERESIS 0.3

static void read_config(long max)
{
    FILE *f=fopen(CONFIG,"r");
    char line[256];
    if(!f)
        return;
    while(fgets(line,sizeof(line),f))
    {
        double c[NCAL];
        long lo,hi;
        if(sscanf(line," cal %lf %lf %lf %lf %lf",&c[0],&c[1],&c[2],&c[3],&c[4])==NCAL)
        {
            int ok=c[0]>0;
            for(int i=1;i<NCAL;i++)
                if(c[i]<=c[i-1]) ok=0;
            if(ok)
                memcpy(cal,c,sizeof(cal));
            else
                fprintf(stderr,"pyra_volumed: %s: cal must be positive and rising, ignored\n",CONFIG);
        }
        else if(sscanf(line," range %ld %ld",&lo,&hi)==2)
        {
            if(lo>=0 && lo<hi && hi<=max)
            {
                step_lo=lo;
                step_hi=hi;
            }
            else
                fprintf(stderr,"pyra_volumed: %s: range must be 0 <= lo < hi <= %ld, ignored\n",CONFIG,max);
        }
    }
    fclose(f);
}

// how far round the wheel is, 0..1
static double travel(double raw)
{
    if(raw<=cal[0])
        return 0;
    for(int i=1;i<NCAL;i++)
        if(raw<=cal[i])
            return (i-1+log(raw/cal[i-1])/log(cal[i]/cal[i-1]))/(NCAL-1);
    return 1;
}

// where the wheel is, in fractional control steps
static double position(double raw)
{
    if(raw<=RAW_OFF)
        return 0;
    return step_lo+travel(raw)*(step_hi-step_lo);
}



int main(int argc,char **argv)
{
    struct iio_context *ctx;
    ctx=iio_create_default_context();


    long min,max;
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;
    int delay=MIN_DELAY;

    snd_mixer_open(&handle,0);
    snd_mixer_attach(handle,CARD);
    snd_mixer_selem_register(handle,NULL,NULL);
    snd_mixer_load(handle);
    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_index(sid, 0);
    snd_mixer_selem_id_set_name(sid, SELEM);
    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    snd_mixer_selem_get_playback_volume_range(elem, &min, &max);
    if(step_hi>max)
        step_hi=max;
    read_config(max);
    

    const struct iio_device *dev=iio_context_find_device(ctx,DEVNAME);
    if(dev)
    {
        //printf("found device\n");
        struct iio_channel *ch=iio_device_find_channel(dev,CHANNEL,0);
        if(ch)
        {
            //printf("found channel\n");
            const char *attr=iio_channel_find_attr(ch,"input");
            const char *attraw=iio_channel_find_attr(ch,"raw");
            double val;
            double raw;
            long pv=-1;
            while(true)
            { 
                //iio_channel_attr_read_double(ch,attr,&val);
                iio_channel_attr_read_double(ch,attraw,&raw);
                double pos=position(raw);
                long volume=lround(pos);
                if(pv<0 || (volume!=pv && fabs(pos-pv)>0.5+HYSTERESIS))
                    {
                        snd_mixer_selem_set_playback_volume_all(elem, volume);
                        pv=volume;
			delay=MIN_DELAY;
                    }
		else
		    {
		     delay+=delay/10;
		     if (delay > MAX_DELAY) delay=MAX_DELAY;
		    }
	            //printf("i:%f : r:%f : v:%d d:%d\n",val,raw,volume,delay);
                usleep(delay);	
            }  
        }

    }

iio_context_destroy(ctx);
snd_mixer_close(handle);

return 0;
}

