#!/bin/bash

# constants

fsdir="/usr/share/vnx/filesystems"
baseaddress="http://idefix.dit.upm.es/vnx/filesystems/"
createsymlink=""
rootfs_spec=""


# Return name of symbolic link for a root_fs
function makeLinkName {
   if [[ $1 == *ubuntu* ]] ; then
      if [[ $1 == *gui* ]] ; then
         echo "rootfs_ubuntu-gui"
      else
         echo "rootfs_ubuntu"
      fi
   fi
   if [[ $1 == *freebsd* ]] ; then
      if [ $1 == *gui* ] ; then
         echo "rootfs_freebsd-gui"
      else
         echo "rootfs_freebsd"
      fi
   fi
   if [[ $1 == *fedora* ]] ; then
      if [[ $1 == *gui* ]] ; then
         echo "rootfs_fedora-gui"
      else
         echo "rootfs_fedora"
      fi
   fi
   if [[ $1 == *centos* ]] ; then
      if [[ $1 == *gui* ]] ; then
         echo "rootfs_centos-gui"
      else
         echo "rootfs_centos"
      fi
   fi
   if [[ $1 == *uml* ]] ; then
      if [[ $1 == *debian* ]] ; then
         echo "rootfs_tutorial"
      else
         echo "rootfs_light"
      fi
   fi

   
}


function install {

   if [ ! $rootfs_spec = "" ] ; then
      # try to download and install specified rootfs

    #baseaddress="http://idefix.dit.upm.es/vnx/filesystems/"
    #rootfs_spec="vnx_rootfs_kvm_centos-5.6-gui-v021.qcow2.bz"
      myurl=(${baseaddress}${rootfs_spec})
      echo "myurl=$myurl"
      error404=""
      cd $fsdir
      wget $myurl || error404="true"
    #echo $error404
      if [ $error404 = "true" ] ; then
         echo "Filesystem not found on the server."
         install_interactive
         exit
      fi
      echo ""
      echo "Extracting $rootfs_spec..."
      
      bunzip2 $rootfs_spec
      #Create symbolic link if -l
      if [ $createsymlink = yes ] ; then
         chosen=$(echo $rootfs_spec | sed -e "s/.bz2//g")
         linkname=$(makeLinkName $chosen)
         echo "Creating simbolic link: $linkname"
         ln -s $chosen $linkname
         echo "$rootfs_spec successfully installed."
         echo ""
         rm $rootfs_spec
      fi
   else
      install_interactive
   fi
}


function install_interactive {

   # show filesystems in server and ask user to choose
   old_IFS=$IFS
   IFS=$'\n'
   arrayfilelinks=($(curl $baseaddress -s | w3m -dump -T text/html | grep bz2))
   IFS=$old_IFS


   while true; do

      # Show filesystems on server in columns
      for (( i = 0 ; i < ${#arrayfilelinks[@]} ; i++ ))
      do
         saveIFS=$IFS
         IFS=$'\n'
         echo ${arrayfilelinks[$i]} | sed -e "s/\[ \]/\[$i\]/g" | column
         IFS=$saveIFS
      done

      # Read choice from user
      echo ""
      echo -n "Add filesystem to compilation (0-`expr ${#arrayfilelinks[@]} - 1`) or finish (f): "
      read choice

      # Check empty choice
      if [[ -z $choice ]] ; then
         echo "Your choice is not valid, please try again."
         echo ""
         sleep 2
         continue
      fi

      # Check for choice f = finish installing filesystems
      if [ $choice = f ] ; then
         echo "Finishing..."
         sleep 1
         break
      fi

      # Check that chosen number is on the list (0<=$choice<=max) and install
      if [ $choice -ge 0 ] ; then 
         if [ $choice -le `expr ${#arrayfilelinks[@]} - 1` ] ; then

            chosenbz2=$(echo ${arrayfilelinks[$choice]} | awk '{print $3}')
            chosen=$(echo $chosenbz2 | sed -e "s/.bz2//g")
            chosenbz2url=(${baseaddress}${chosenbz2})
            chosenmd5=$(echo ${arrayfilelinks[$choice]/.bz2/.md5} | awk '{print $3}')
            chosenmd5url=(${baseaddress}${chosenmd5}) 
            cd $fsdir
            wget -N $chosenbz2url
            echo "Extracting $chosenbz2..."
            bunzip2 $chosenbz2
            # Create symbolic link if -l
            if [ $createsymlink = yes ] ; then
               linkname=$(makeLinkName $chosen )
               echo "Creating simbolic link: $linkname"
               ln -s $chosen $linkname
               echo "$chosenbz2 successfully installed."
               echo ""
               rm $chosenbz2
               sleep 1
            fi
            continue
         fi

         echo "Your choice is not valid, please try again."
         echo ""
         sleep 2
         continue
      fi
   
   done
}




# Option -r vnx_rootfs_...qcow2.bz2 -> download specified fs and install
# Option -l -> Create symbolic link (createsymlink="yes")
OPTIND=1
while getopts ":l :r:" opt; do
  case $opt in
    l)
      #echo "-l was triggered" >&2
      createsymlink="yes"
      ;;
    r)
      #echo "-r was triggered, Parameter: $OPTARG" >&2
      rootfs_spec=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

install

exit 0






