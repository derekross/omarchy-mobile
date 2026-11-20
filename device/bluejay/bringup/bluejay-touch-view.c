/* SPDX-License-Identifier: MIT */
/* Bounded framebuffer/evdev diagnostic. No MMIO, driver load, grab, or storage IO. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

enum { W=1080, H=2400, SLOTS=10, BYTES=W*H*4 };
struct contact { int id,x,y; };
struct state {
 struct contact c[SLOTS]; int slot;
 unsigned starts, releases, frames, dropped, edges, keydown[3], keyup[3];
 bool held[3];
};
static uint32_t *screen;
static const uint32_t bg=0xff101b25, grid=0xff263e4c;
static void box(int x,int y,int w,int h,uint32_t color)
{
 for(int j=y;j<y+h;j++) for(int i=x;i<x+w;i++)
  if(i>=0 && i<W && j>=0 && j<H) screen[j*W+i]=color;
}
static void label(int x,int y,const char *text,uint32_t color)
{
 static const struct {char c;unsigned char row[7];} font[]={
  {'P',{30,17,17,30,16,16,16}},{'W',{17,17,17,21,21,21,10}},
  {'R',{30,17,17,30,20,18,17}},{'V',{17,17,17,17,17,10,4}},
  {'O',{14,17,17,17,17,17,14}},{'L',{16,16,16,16,16,16,31}},
  {'T',{31,4,4,4,4,4,4}},{'U',{17,17,17,17,17,17,14}},
  {'C',{14,17,16,16,16,17,14}},{'H',{17,17,17,31,17,17,17}},
  {'E',{31,16,16,30,16,16,31}},{'S',{15,16,16,14,1,1,30}},
  {'B',{30,17,17,30,17,17,30}},{'N',{17,25,25,21,19,19,17}},
  {'A',{14,17,17,31,17,17,17}},
  {'+',{0,4,4,31,4,4,0}},{'-',{0,0,0,31,0,0,0}}};
 for(;*text;text++,x+=48)for(unsigned g=0;g<sizeof(font)/sizeof(font[0]);g++)
  if(font[g].c==*text)for(int j=0;j<7;j++)for(int i=0;i<5;i++)
   if(font[g].row[j]&(1U<<(4-i)))box(x+i*8,y+j*8,8,8,color);
}
static void key_indicator(int i,int state)
{
 box(100+i*300,180,280,90,state==1?0xffffc266:state==2?0xff5ddbb0:grid);
 label(100+i*300+(i?44:68),196,i==0?"PWR":i==1?"VOL+":"VOL-",state?bg:0xffd5e8ed);
}
static void base(void)
{
 for(int i=0;i<W*H;i++) screen[i]=bg;
 for(int x=0;x<W;x+=108) box(x,0,2,H,grid);
 for(int y=0;y<H;y+=120) box(0,y,W,2,grid);
 box(0,0,W,8,0xff5ddbb0);box(0,H-8,W,8,0xff5ddbb0);
 box(0,0,8,H,0xff5ddbb0);box(W-8,0,8,H,0xff5ddbb0);
 /* Three key indicators: power, volume up, volume down. */
 for(int i=0;i<3;i++) key_indicator(i,0);
 label(324,64,"TOUCH TEST",0xffd5e8ed);
}
static int event(struct state *s,const struct input_event *e,bool keys)
{
 if(e->type==EV_SYN && e->code==SYN_DROPPED) { s->dropped++;return -1; }
 if(keys && e->type==EV_KEY) {
  int i=e->code==KEY_POWER?0:e->code==KEY_VOLUMEUP?1:e->code==KEY_VOLUMEDOWN?2:-1;
  if(i<0)return 0;
  if(e->value==1) {s->keydown[i]++;s->held[i]=true;}
  else if(e->value==0) {s->keyup[i]++;s->held[i]=false;}
  else if(e->value!=2)return -1;
  key_indicator(i,s->held[i]?1:2);
 }
 if(keys)return 0;
 if(e->type==EV_ABS) {
  if(e->code==ABS_MT_SLOT) {if(e->value<0||e->value>=SLOTS)return -1;s->slot=e->value;}
  else if(e->code==ABS_MT_TRACKING_ID) {
   struct contact *c=&s->c[s->slot];
   if(e->value>=0) {if(c->id>=0)return -1;s->starts++;}
   else {if(c->id<0)return -1;s->releases++;}
   c->id=e->value;
  } else if(e->code==ABS_MT_POSITION_X) {
   if(e->value<0||e->value>=W)return -1;
   s->c[s->slot].x=e->value;
  } else if(e->code==ABS_MT_POSITION_Y) {
   if(e->value<0||e->value>=H)return -1;
   s->c[s->slot].y=e->value;
  }
 }
 if(e->type==EV_SYN && e->code==SYN_REPORT) {
  s->frames++;
  for(int i=0;i<SLOTS;i++) if(s->c[i].id>=0) {
   int x=s->c[i].x,y=s->c[i].y;
   uint32_t color=i%2?0xffffc266:0xff5ddbb0;
   box(x-6,y-6,13,13,color);box(x-24,y-1,49,3,color);box(x-1,y-24,3,49,color);
   if(x<=54)s->edges|=1;
   if(x>=W-55)s->edges|=2;
   if(y<=120)s->edges|=4;
   if(y>=H-121)s->edges|=8;
  }
 }
 return 0;
}
static double now(void)
{ struct timespec t;if(clock_gettime(CLOCK_MONOTONIC,&t))exit(2);return t.tv_sec+t.tv_nsec/1e9; }
static void init(struct state *s)
{ memset(s,0,sizeof(*s));for(int i=0;i<SLOTS;i++)s->c[i].id=-1; }
static bool held(const struct state *s)
{
 for(int i=0;i<SLOTS;i++)if(s->c[i].id>=0)return true;
 for(int i=0;i<3;i++)if(s->held[i])return true;
 return false;
}
static bool window_open(double t,double deadline,bool active)
{ return t<deadline || (active && t<deadline+5); }
static int selftest(void)
{
 struct state s;init(&s);screen=calloc(1,BYTES);if(!screen)return 2;base();
 if(!window_open(59,60,false)||window_open(60,60,false)||!window_open(60,60,true)||window_open(65,60,true))return 1;
 struct input_event a[]={
  {.type=EV_ABS,.code=ABS_MT_TRACKING_ID,.value=7},
  {.type=EV_ABS,.code=ABS_MT_POSITION_X,.value=0},
  {.type=EV_ABS,.code=ABS_MT_POSITION_Y,.value=2399},
  {.type=EV_SYN,.code=SYN_REPORT},
  {.type=EV_ABS,.code=ABS_MT_TRACKING_ID,.value=-1}};
 for(unsigned i=0;i<sizeof(a)/sizeof(a[0]);i++)if(event(&s,&a[i],false))return 1;
 if(s.starts!=1||s.releases!=1||s.edges!=9||s.c[0].id!=-1)return 1;
 a[0].code=ABS_MT_SLOT;a[0].value=10;if(event(&s,&a[0],false)!=-1)return 1;
 a[0].code=ABS_MT_POSITION_X;a[0].value=-1;if(event(&s,&a[0],false)!=-1)return 1;
 a[0].type=EV_SYN;a[0].code=SYN_DROPPED;if(event(&s,&a[0],false)!=-1)return 1;
 for(int i=0;i<3;i++) {
  struct input_event k={.type=EV_KEY,.code=i==0?KEY_POWER:i==1?KEY_VOLUMEUP:KEY_VOLUMEDOWN,.value=1};
  if(event(&s,&k,true))return 1;
  k.value=0;if(event(&s,&k,true))return 1;
  if(s.keydown[i]!=1||s.keyup[i]!=1||s.held[i])return 1;
 }
 free(screen);puts("PASS: bounds, contact release, edges, dropped-event refusal and three key pairs");return 0;
}
int main(int argc,char **argv)
{
 if(argc==2&&!strcmp(argv[1],"--selftest"))return selftest();
 if(argc==3&&!strcmp(argv[1],"--preview")) {
  screen=calloc(1,BYTES);if(!screen)return 2;base();FILE *f=fopen(argv[2],"wx");
  if(!f)return 2;
  bool good=fwrite(screen,1,BYTES,f)==BYTES;if(fclose(f))good=false;free(screen);return good?0:2;
 }
 if(argc!=4) {fputs("usage: bluejay-touch-view TOUCH_EVENT KEYS_EVENT SECONDS | --probe TOUCH_EVENT KEYS_EVENT | --selftest | --preview FILE\n",stderr);return 2;}
 bool probe=!strcmp(argv[1],"--probe");
 char *end;long seconds=0;
 if(!probe) {seconds=strtol(argv[3],&end,10);if(*end||seconds<1||seconds>60)return 2;}
 int fb=open("/dev/fb0",(probe?O_RDONLY:O_RDWR)|O_CLOEXEC),fd[2]={-1,-1};
 struct fb_fix_screeninfo fix;struct fb_var_screeninfo var;
 if(fb<0||ioctl(fb,FBIOGET_FSCREENINFO,&fix)||ioctl(fb,FBIOGET_VSCREENINFO,&var))return 2;
 if(strncmp(fix.id,"simpledrm",9)||var.xres!=W||var.yres!=H||var.bits_per_pixel!=32||
    var.xoffset||var.yoffset||fix.line_length!=W*4||fix.smem_len<BYTES||
    var.red.offset!=16||var.green.offset!=8||var.blue.offset||var.red.length!=8||var.green.length!=8||var.blue.length!=8)return 2;
 for(int i=0;i<2;i++) {
  fd[i]=open(argv[i+(probe?2:1)],O_RDONLY|O_NONBLOCK|O_CLOEXEC);char name[128]={0};
  if(fd[i]<0||ioctl(fd[i],EVIOCGNAME(sizeof(name)),name)<0||strcmp(name,i?"gpio-keys":"ALIX Touchscreen"))return 2;
  if(!probe) {int clockid=CLOCK_MONOTONIC;if(ioctl(fd[i],EVIOCSCLOCKID,&clockid))return 2;}
 }
 struct input_absinfo slot,x,y;
 if(ioctl(fd[0],EVIOCGABS(ABS_MT_SLOT),&slot)||slot.minimum!=0||slot.maximum!=9||
    ioctl(fd[0],EVIOCGABS(ABS_MT_POSITION_X),&x)||x.minimum!=0||x.maximum!=W-1||
    ioctl(fd[0],EVIOCGABS(ABS_MT_POSITION_Y),&y)||y.minimum!=0||y.maximum!=H-1)return 2;
 int32_t ids[SLOTS+1]={ABS_MT_TRACKING_ID};
 if(ioctl(fd[0],EVIOCGMTSLOTS(sizeof(ids)),ids))return 2;
 for(int i=1;i<=SLOTS;i++)if(ids[i]!=-1)return 2;
 unsigned char keys[(KEY_MAX+8)/8];memset(keys,0,sizeof(keys));
 if(ioctl(fd[1],EVIOCGKEY(sizeof(keys)),keys)<0)return 2;
 for(int i=0;i<3;i++) {
  int code=i==0?KEY_POWER:i==1?KEY_VOLUMEUP:KEY_VOLUMEDOWN;
  if(keys[code/8]&(1U<<(code%8)))return 2;
 }
 if(probe) {puts("PASS: read-only framebuffer geometry/format, input identities/axes/slots and initial contacts/keys all released");close(fb);close(fd[0]);close(fd[1]);return 0;}
 struct state s;init(&s);s.slot=slot.value;
 if(s.slot<0||s.slot>=SLOTS)return 2;
 screen=mmap(NULL,BYTES,PROT_READ|PROT_WRITE,MAP_SHARED,fb,0);if(screen==MAP_FAILED)return 2;base();
 double started=now(),deadline=started+seconds;int failed=0;bool cue=false,grace=false;
 printf("VISUAL_CAPTURE_READY monotonic=%.6f seconds=%ld release_grace=5 event_clock=MONOTONIC\n",started,seconds);fflush(stdout);
 while(window_open(now(),deadline,held(&s))&&!failed) {
  double remaining=deadline-now();
  if(!cue&&(s.edges==15||remaining<=20)) {
   puts("BUTTON_PHASE_NOW: briefly tap Power, Volume Up and Volume Down, then release everything.");fflush(stdout);
   label(276,310,"BUTTONS NOW",0xffffc266);cue=true;
  }
  if(!grace&&remaining<=0) {puts("RELEASE_EVERYTHING_NOW");fflush(stdout);grace=true;}
  int width=(int)((W-80)*(remaining>0?remaining/seconds:0));
  box(40,H-60,W-80,12,grid);box(40,H-60,width,12,0xff5ddbb0);
  struct pollfd p[2]={{.fd=fd[0],.events=POLLIN},{.fd=fd[1],.events=POLLIN}};
  int r=poll(p,2,100);if(r<0) {if(errno==EINTR)continue;failed=1;break;}
  for(int i=0;i<2;i++) {
   if(p[i].revents&(POLLERR|POLLHUP|POLLNVAL)) {failed=1;break;}
   if(p[i].revents&POLLIN) {
    struct input_event events[64];ssize_t n=read(fd[i],events,sizeof(events));
    if(n<0&&(errno==EAGAIN||errno==EINTR))continue;
    if(n<=0||n%(ssize_t)sizeof(events[0])) {failed=1;break;}
    for(size_t j=0;j<(size_t)n/sizeof(events[0]);j++) {
     printf("EVENT %d %lld %lld %u %u %d\n",i,(long long)events[j].time.tv_sec,(long long)events[j].time.tv_usec,events[j].type,events[j].code,events[j].value);
     if(event(&s,&events[j],i==1))failed=1;
    }
   }
  }
 }
 int active=0;bool released=true;for(int i=0;i<SLOTS;i++)active+=s.c[i].id>=0;
 ids[0]=ABS_MT_TRACKING_ID;if(ioctl(fd[0],EVIOCGMTSLOTS(sizeof(ids)),ids))failed=1;
 for(int i=1;i<=SLOTS;i++)if(ids[i]!=-1)released=false;
 memset(keys,0,sizeof(keys));if(ioctl(fd[1],EVIOCGKEY(sizeof(keys)),keys)<0)failed=1;
 for(int i=0;i<3;i++) {
  int code=i==0?KEY_POWER:i==1?KEY_VOLUMEUP:KEY_VOLUMEDOWN;
  if(keys[code/8]&(1U<<(code%8)))released=false;
 }
 for(int i=0;i<3;i++)if(s.held[i]||s.keydown[i]!=s.keyup[i])released=false;
 bool complete=released&&!active&&s.starts&&s.starts==s.releases&&s.edges==15;
 for(int i=0;i<3;i++)if(!s.keydown[i]||s.keydown[i]!=s.keyup[i])complete=false;
 printf("{\"starts\":%u,\"releases\":%u,\"frames\":%u,\"active\":%d,\"edges\":%u,\"dropped\":%u,\"power\":[%u,%u],\"volume_up\":[%u,%u],\"volume_down\":[%u,%u],\"failed\":%s,\"released\":%s,\"coverage_complete\":%s,\"elapsed\":%.6f}\n",s.starts,s.releases,s.frames,active,s.edges,s.dropped,s.keydown[0],s.keyup[0],s.keydown[1],s.keyup[1],s.keydown[2],s.keyup[2],failed?"true":"false",released?"true":"false",complete?"true":"false",now()-started);
 munmap(screen,BYTES);close(fb);close(fd[0]);close(fd[1]);
 /* Incomplete owner coverage is a partial result, not a transport/kernel fault. */
 return failed?1:complete?0:3;
}
