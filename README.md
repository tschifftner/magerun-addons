MageRun Addons
==============

Some additional commands for N98-MageRun Magento command-line tool.


Installation
------------
There are a few options.  You can check out the different options in the [MageRun
docs](http://magerun.net/introducting-the-new-n98-magerun-module-system/).

Here's the easiest:

1. Create ~/.n98-magerun/modules/ if it doesn't already exist.

        mkdir -p ~/.n98-magerun/modules/

2. Clone the magerun-addons repository in there

        cd ~/.n98-magerun/modules/ && git clone git@github.com:tschifftner/magerun-addons.git

3. It should be installed. To see that it was installed, check to see if one of the new commands is in there, like `order:setstatus:complete`.

        n98-magerun.phar help order:setstatus:complete

Commands
--------

### Set order complete status ###

This commands creates missing invoices and shipments and sets order status to complete.

    $ n98-magerun.phar order:setstatus:complete [--increment-ids[="100004200-100004250,100003175"]] [--confirm-all]

Every order has to be confirmed manually if ```--config-all``` is not set.

To limit the orders you can specify single, comma separated and ranges of increment ids. You can even combine those like ```--increment-ids=100004215,100004219,100004227-100004238```


### Generate project helper ###

Project helper allow to easily install Projects. _This works for prepared projects on aws s3 only._

    $ n98-magerun.phar project:helper:create


Credits due where credits due
--------

 - [magerun](https://github.com/netz98/n98-magerun/)
 - This readme is based on the readme of [Kalen Jordan addon](https://github.com/kalenjordan/magerun-addons/)
