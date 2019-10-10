// pyra volumed
// reads volumewheel value and applies it to the mixer
// temporary daemon, should be made part of the input daemon


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <alsa/asoundlib.h>
#include <unistd.h>
#include <iio.h>


#define DEVNAME "palmas-gpadc"
#define CHANNEL "voltage2"

#define CARD "hw:CARD=L15"

#define SELEM "Handsfree"

int main(int argc,char **argv)
{
    struct iio_context *ctx;
    ctx=iio_create_default_context();


    long min,max;
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;


    snd_mixer_open(&handle,0);
    snd_mixer_attach(handle,CARD);
    snd_mixer_selem_register(handle,NULL,NULL);
    snd_mixer_load(handle);
    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_index(sid, 0);
    snd_mixer_selem_id_set_name(sid, SELEM);
    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    snd_mixer_selem_get_playback_volume_range(elem, &min, &max);
    

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
            int pv=-1;
            while(true)
            { 
                //iio_channel_attr_read_double(ch,attr,&val);
                iio_channel_attr_read_double(ch,attraw,&raw);
                long volume=raw*max/2052;
                if(volume!=pv) 
                    {
                        snd_mixer_selem_set_playback_volume_all(elem, volume);
                        pv=volume;
                    }
	            //printf("%f : %f : %d \n",val,raw,volume);
                usleep(100000);	
            }  
        }

    }

iio_context_destroy(ctx);
snd_mixer_close(handle);

return 0;
}

