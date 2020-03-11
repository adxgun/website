---
title: "How to resize images for better upload/download performance. Android Development."
date: 2017-09-04 00:00:00 +0000
draft: false
---

Its not very common to see a project that doesn’t require photo upload in one form or the other. Most high end android device today create a photo as big as 2MB. This is a problem, How? Imagine you are building a mobile app that require your users to have a profile picture, having scalabilty in mind, each photo must not be > 100KB, am i right?. You dont want to save a 1MB photo for each user. It will not only affect your UX, your server would suffer as well. Uploading large photo to remote server can cause one or all of the following problems

* Slow upload/download operation on devices with low network bandwidth

* Affect product scalability

* And MORE…

### SOLUTION

The real obvious solution is to have the photo resized before sending to remote server. Good!. But, how? Thats what i am trying to show.

I had little problem figuring out how i would solve this when i started writting apps for android, so i just decided to share it today. I am looking forward to seeing someone that will show me a better way of doing it. Lets go!

### **Assumption**

* I assume you are convenient with Java programming language(Thats what i’ll be using, you can easily grab it if you have experience with other programming languages too.)

* Have android studio and SDK installed and ready.

* Create a new android studio project. I call mine EasyPhotoUpload

![](https://cdn-images-1.medium.com/max/2732/1*YuJYPjO6KHQv4zCprHlEHA.png)

Project name — EasyPhotoUpload

Min SDK — 4.0.3, API 15

Basically, we are trying to

* Let user select photo from Gallery

* Get the selected photo path

* Resize the selected photo on a background thread and return the result to the main thread — As you’ll see, resizing image is an expensive operation and must not be performed on the main thread

The final code for this article is available on github — [https://github.com/adigunhammedolalekan/easyphotoupload](https://github.com/adigunhammedolalekan/easyphotoupload)

Once android studio finished building the project and you are all ready, create these packages — core, listeners, utils

![](https://cdn-images-1.medium.com/max/2732/1*DyCVICAyc6rdKEEUzStL1Q.png)

Under util package, create a new class, Util.java, the following is the content of the file.

‘public class Util {

//SDF to generate a unique name for the compressed file.
 public static final SimpleDateFormat SDF = new SimpleDateFormat(“yyyymmddhhmmss”, Locale.getDefault());

/*
 compress the file/photo from [@param](http://twitter.com/param) <b>path</b> to a private location on the current device and return the compressed file.
 [@param](http://twitter.com/param) path = The original image path
 [@param](http://twitter.com/param) context = Current android Context
 */
 public static File getCompressed(Context context, String path) throws IOException {

if(context == null)
 throw new NullPointerException(“Context must not be null.”);
 //getting device external cache directory, might not be available on some devices,
 // so our code fall back to internal storage cache directory, which is always available but in smaller quantity
 File cacheDir = context.getExternalCacheDir();
 if(cacheDir == null)
 //fall back
 cacheDir = context.getCacheDir();

String rootDir = cacheDir.getAbsolutePath() + “/ImageCompressor”;
 File root = new File(rootDir);

//Create ImageCompressor folder if it doesnt already exists.
 if(!root.exists())
 root.mkdirs();

//decode and resize the original bitmap from [@param](http://twitter.com/param) path.
 Bitmap bitmap = decodeImageFromFiles(path, /* your desired width*/300, /*your desired height*/ 300);

//create placeholder for the compressed image file
 File compressed = new File(root, SDF.format(new Date()) + “.jpg” /*Your desired format*/);

//convert the decoded bitmap to stream
 ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();

/*compress bitmap into byteArrayOutputStream
 Bitmap.compress(Format, Quality, OutputStream)

Where Quality ranges from 1–100.
 */
 bitmap.compress(Bitmap.CompressFormat.JPEG, 80, byteArrayOutputStream);

/*
 Right now, we have our bitmap inside byteArrayOutputStream Object, all we need next is to write it to the compressed file we created earlier,
 java.io.FileOutputStream can help us do just That!

*/
 FileOutputStream fileOutputStream = new FileOutputStream(compressed);
 fileOutputStream.write(byteArrayOutputStream.toByteArray());
 fileOutputStream.flush();

fileOutputStream.close();

//File written, return to the caller. Done!
 return compressed;
 }

public static Bitmap decodeImageFromFiles(String path, int width, int height) {
 BitmapFactory.Options scaleOptions = new BitmapFactory.Options();
 scaleOptions.inJustDecodeBounds = true;
 BitmapFactory.decodeFile(path, scaleOptions);
 int scale = 1;
 while (scaleOptions.outWidth / scale / 2 >= width
 && scaleOptions.outHeight / scale / 2 >= height) {
 scale *= 2;
 }
 // decode with the sample size
 BitmapFactory.Options outOptions = new BitmapFactory.Options();
 outOptions.inSampleSize = scale;
 return BitmapFactory.decodeFile(path, outOptions);
 }
}’

The method that handles photo compression and storage is ‘static File getCompressed(Context, String)’, as you’ve seen from the code above, this method takes a path to a photo existing on the device, resize it, store it in a private location on the device and returns the newly compressed file. Voila!

The next file we’ll examine is called ImageCompressTask.java, this class implements a Runnable, with a three arguments constructor and in its run() method, the compression happens all in the background thread, it then post the final result to the main thread with the help of android.os.Handler or report the error otherwise.

ImageCompressTask.java

‘**public class **ImageCompressTask **implements **Runnable {

**private **Context **mContext**;
 **private **List<String> **originalPaths **= **new **ArrayList<>();
 **private **Handler **mHandler **= **new **Handler(Looper.*getMainLooper*());
 **private **List<File> **result **= **new **ArrayList<>();
 **private **IImageCompressTaskListener **mIImageCompressTaskListener**;

**public **ImageCompressTask(Context context, String path, IImageCompressTaskListener compressTaskListener) {

**originalPaths**.add(path);
 **mContext **= context;

**mIImageCompressTaskListener **= compressTaskListener;
 }
 **public **ImageCompressTask(Context context, List<String> paths, IImageCompressTaskListener compressTaskListener) {
 **originalPaths **= paths;
 **mContext **= context;
 **mIImageCompressTaskListener **= compressTaskListener;
 }
 @Override
 **public void **run() {

**try **{

*//Loop through all the given paths and collect the compressed file from Util.getCompressed(Context, String)
 ***for **(String path : **originalPaths**) {
 File file = Util.*getCompressed*(**mContext**, path);
 *//add it!
 ***result**.add(file);
 }
 *//use Handler to post the result back to the main Thread
 ***mHandler**.post(**new **Runnable() {
 @Override
 **public void **run() {

**if**(**mIImageCompressTaskListener **!= **null**)
 **mIImageCompressTaskListener**.onComplete(**result**);
 }
 });
 }**catch **(**final **IOException ex) {
 *//There was an error, report the error back through the callback
 ***mHandler**.post(**new **Runnable() {
 @Override
 **public void **run() {
 **if**(**mIImageCompressTaskListener **!= **null**)
 **mIImageCompressTaskListener**.onError(ex);
 }
 });
 }
 }
}’

Finally, create MainActivity.java, the UI for the whole sample App.

MainActivity.java

‘
public class MainActivity extends AppCompatActivity {

Button selectImage;
 ImageView selectedImage;

private static final int REQUEST_STORAGE_PERMISSION = 100;
 private static final int REQUEST_PICK_PHOTO = 101;

//create a single thread pool to our image compression class.
 private ExecutorService mExecutorService = Executors.newFixedThreadPool(1);

private ImageCompressTask imageCompressTask;

[@Override](http://twitter.com/Override)
 protected void onCreate(Bundle savedInstanceState) {
 super.onCreate(savedInstanceState);
 setContentView(R.layout.activity_main);

selectedImage = (ImageView) findViewById(R.id.iv_selected_photo);
 selectImage = (Button) findViewById(R.id.btn_select_image);

selectImage.setOnClickListener(new View.OnClickListener() {
 [@Override](http://twitter.com/Override)
 public void onClick(View view) {
 requestPermission();
 }
 });
 }

void requestPermission() {

if(PackageManager.PERMISSION_GRANTED !=
 ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
 if(ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)) {
 ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE},
 REQUEST_STORAGE_PERMISSION);
 }else {
 //Yeah! I want both block to do the same thing, you can write your own logic, but this works for me.
 ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE},
 REQUEST_STORAGE_PERMISSION);
 }
 }else {
 //Permission Granted, lets go pick photo
Intent intent = **new **Intent(Intent.***ACTION_PICK***);
intent.setAction(Intent.***ACTION_GET_CONTENT***);
intent.setType(**“image/*”**);
startActivityForResult(intent, ***REQUEST_PICK_PHOTO***);
 }

}

[@Override](http://twitter.com/Override)
 protected void onActivityResult(int requestCode, int resultCode, Intent data) {
 super.onActivityResult(requestCode, resultCode, data);
 if(requestCode == REQUEST_PICK_PHOTO && resultCode == RESULT_OK &&
 data != null) {
 //extract absolute image path from Uri
 Uri uri = data.getData();
 Cursor cursor = MediaStore.Images.Media.query(getContentResolver(), uri, new String[]{MediaStore.Images.Media.DATA});
 if(cursor != null) {
 String path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA));

//Create ImageCompressTask and execute with Executor.
 imageCompressTask = new ImageCompressTask(this, path, iImageCompressTaskListener);

mExecutorService.execute(imageCompressTask);
 }
 }
 }

//image compress task callback
 private IImageCompressTaskListener iImageCompressTaskListener = new IImageCompressTaskListener() {
 [@Override](http://twitter.com/Override)
 public void onComplete(List<File> compressed) {
 //photo compressed. Yay!

//prepare for uploads.

File file = compressed.get(0);

selectedImage.setImageBitmap(BitmapFactory.decodeFile(file.getAbsolutePath()));
 }

[@Override](http://twitter.com/Override)
 public void onError(Throwable error) {
 //very unlikely, but it might happen on a device with extremely low storage.
 //log it, log.WhatTheFuck?, or show a dialog asking the user to delete some files….etc, etc
 Log.wtf(“ImageCompressor”, “Error occurred”, error);
 }
 };

[@Override](http://twitter.com/Override)
 protected void onDestroy() {
 super.onDestroy();

//clean up!
 mExecutorService.shutdown();

mExecutorService = null;
 imageCompressTask = null;
 }
}’

All the codes are well commented, but if you have problem with any part. Do let me know! All the codes are on github, visit it for better view. The screenshoot from the final result.

I’ll love your contribution to this. Thanks!

![](https://cdn-images-1.medium.com/max/2000/1*Ft4n6WXie7yij3_bEghHIQ.png)

### About Me

I am a passionate mobile app developer with 2.5+ experience building great apps for the android platform. If you need my talent, feel free to contact me!

Github — [www.github.com/adigunhammedolalekan](http://www.github.com/adigunhammedolalekan)

Mail — adigunhammed.lekan@gmail.com

Contact — 07035452307
