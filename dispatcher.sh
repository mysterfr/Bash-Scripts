#!/bin/bash

#### Ce script a pour but de faire un disptaching de fichiers de séries TV dans une arborescende propre.
#### Last update : 2013-02-10 - Myster_fr

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Un peu de couleur ne fait pas de mal
RED="\033[31m"
RESET="\033[0m"
GREEN="\033[32m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
YELLOW="\033[1;33m"

### HEADER ###

LOCKFILE="/var/lock/`basename $0`"
LOCKFD=99

# PRIVATE
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# ON START
_prepare_locking

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
exlock()            { _lock x; }   # obtain an exclusive lock
shlock()            { _lock s; }   # obtain a shared lock
unlock()            { _lock u; }   # drop a lock

### BEGIN OF SCRIPT ###

exlock_now || exit 1

# Dossier source dans lequel chercher les fichiers a copier
# Il s'agit en general d'un point de montage NFS
SOURCE="/mnt/Octopus/torrents/"						

# Dossier "temporaire" dans lequel tous les fichiers sont transferes, avant dispatch
DEST="/data/test"									

# Dossier racine de destination lors du dispatch. (Repository final) 
# C'est dans ce dossier que seront crees les arborescences pour chaque serie.
REPO="/mnt/Epice_Media/Movie/Series"				

# Nb de jours d'historique a traiter
HIST="3"        					
				
# ATTENTION
# La variable SERIES contient les patterns de chaque serie a transfere
# Les patterns sont separes par un PIPE (|)
SERIES="arrow|homeland|game.of.thrones|revolution.2012|grimm|dont.trust.the.bitch|falling.skies|the.big.bang|how.i|dexter|breaking.bad|fringe|grey|misfits|the.mentalist|the.walking.dead|revenants|touch|elementary|girls|new.girl|rizzoli|vikings|mad.men|community|defiance";
#SERIES="homeland|falling.skies|The.Walking.Dead";

## ATTENTION
# La variable EXCLUDE contient les patterns a exclure
#
# Separer les patterns avec un PIPE, echapper les caracteres speciaux a l'aide de \ 
# Toujours conserver "doing/" et "watch/"
# 
EXCLUDE="doing\/|watch\/|.nfo|.mp3|.avi|.mp4|fastsub|webdl|web.dl|web-dl";
#
TS=`date +%Y%m%d-%H.%M` 							# TimeStamp
FILELIST="/tmp/dispatcher_list_$TS"					# Fichier contenant la liste des fichiers a transferer

umask 0007
# On change temporairement le comportement du shell pour que les commandes soient insensibles
# a la casse aussi souvent que possible
shopt -s nocasematch


### VERIFICATION QUE LES POINTS DE MONTAGE SONT BIEN PRESENTS
# 
# 1. Controle du montage de la source
if [[ ! -f /mnt/Octopus/.is_mounted ]] 
then 
        umount -f /mnt/Octopus ;
		mount -t nfs 10.9.8.1:/data /mnt/Octopus ;
fi
#
# 2. Controle du montage de la destination (REPOSITORY)
# (Commenter les lignes ci-dessous si le REPOSITORY est local.
if [[ ! -f /mnt/Epice_Media/.is_mounted ]] 
then
        umount -f /mnt/Epice_Jojo/; 
        mount -t nfs 10.25.0.5:/volume1/Media /mnt/Epice_Media/ ;
fi


#On se place dans le dossier temporaire
cd $DEST

# On purge le dossier local des fichiers plus anciens (plus de 10j)
find $DEST -mtime +10 -iname "*S[0-9][[0-9]E[0-9][0-9]*" -type f -exec rm -rf {} \;


#On recupere les fichiers d'apres leur nommage SxxExx 
# --- NOUVELLE METHODE ---
# Desormais on recherche tous les fichiers ayant le pattern SxxExx, puis on filtre la liste des fichiers obtenus en :
# 1. Excluant les patterns non voulus (variable EXCLUDE), comme par exemple FASTSUB
# 2. En ne gardant que les fichiers donc le nom contient un pattern de serie (variable SERIES).
#    Les patterns contenus dans la variable SERIES doivent etre separes par un PIPE (syntaxe REGEX, PIPE = "OU")
echo -e "\n$RED Analyse des fichiers disponibles en cours...$RESET\n"
find $SOURCE -mtime -$HIST -iname "*S[0-9][0-9]E[0-9][0-9]*" -type f -printf "%P\n" | sort | egrep -iv "$EXCLUDE" | egrep -i "$SERIES" >> $FILELIST
echo -e "\n$GREEN Fichiers à transférer :$RESET\n"
cat $FILELIST

# Ancienne methode ci-dessous :
# Attention, les pattern de series doivent etre alors separes par un espace au lieu d'un pipe |
# Ici on bouclait sur le pattern et on effectuait donc un find par serie... pas tres optimise
#for i in $SERIES
#        do
#		find $SOURCE -mtime -$HIST -iname "*$i*S[0-9][0-9]E[0-9][0-9]*" -type f -printf "%P\n" | sort | egrep -iv "$EXCLUDE" >> $FILELIST
#done
#cat $FILELIST


#######################################################################################
#######################################################################################
#
# Et c'est parti pour les transferts
#
# NOUVELLE METHODE :
/usr/bin/rsync -vt -P --no-dirs --no-R --files-from=$FILELIST $SOURCE $DEST;


#######################################################################################
#######################################################################################
#
# On peut attaquer la phase de dispatch
#
# On commence par renommer les fichiers EPZ vers un nom valide
# Ex : on part de Epz-Toto.101.blabla pour arriver a Toto.S01E01.blabla
#
for i in `find $DEST -type f -iname "EPZ*" -printf "%P\n"`; 
        do FINAL=`echo $i | sed -e 's/Epz\-\(.*\)\.\([0-9]\)\([0-9][0-9]\)/\1.S0\2E\3/I'  -e 's/\(.\)/\L\1/g' -e 's/\<./\u&/g'`; 
        mv $DEST/$i $DEST/$FINAL; 
done

# On renomme Revolution.2012 en Revolution
# Purement cosmetique, utile pour le scraper XBMC
#
rename -f 's/Revolution.2012/Revolution/' *

# On fait un peu de menage dans le dossier temporaire
# pour supprimer les fichiers "parasites"
# En theorie inutile si la variable EXCLUDE est bien remplie... :)
rm -rf $DEST/*.[Nn]fo
rm -rf $DEST/*.[Mm][Pp]3

# On homogenise les droits sur les fichiers.
chmod 755 $DEST/*


# On distribue tous les fichiers dans des repertoires a leur nom et sous-rep avec saison
for i in `find $DEST -name "*[sS][0-9][[0-9][Ee][0-9][0-9]*" -type f  -printf "%P\n" | sort`; 
	do 
	if [[ ${i%.*} =~ VOSTFR|FRENCH ]]	
	then
		# Ici on utilise SED pour extraire le nom de la série : on capture donc le nom, la saison et la langue
		# \ puis on ne garde que le nom et la langue, on passe alors la chaine en minuscules
		# \ puis on repasse la premiere lettre de chaque mot en majuscule, et enfin le dernier mot (la langue) en majuscules
		# \ Exemple : du nom de fichier "Greys.Anatomy.S08E02.VOSTFR.720P.WEB-DL.DD5.1.H264-ATeam.mkv" on obtient "Greys.Anatomy.VOSTFR"
		SERIE=`echo ${i%.*} | sed -e 's/\(.*\)\.\([sS][0-9][0-9]\).*\(FRENCH\|VOSTFR\).*/\1/I' -e 's/\(.\)/\L\1/g' -e 's/\<./\u&/g' `;
		LANGUE=`echo ${i%.*} | sed -e 's/\(.*\)\.\([sS][0-9][0-9]\).*\(FRENCH\|VOSTFR\).*/\3/I' -e 's/\(.*\)/\U\1/g'`;
		echo -e "$GREEN Langue identifiée ($LANGUE), c'est parti : $RESET"
		# On procede a un traitment similaire pour extraire le numero de la saison.
		SAISON=`echo ${i%.*} | sed -e 's/\(.*\)\.\([sS][0-9][0-9]\).*\(FRENCH\|VOSTFR\).*/\2/I' -e 's/\(.*\)/\U\1/g' -e 's/S/Saison./' `;

	else
		echo -e "\n$RED Langue absente du nom du fichier, FRENCH choisi par défaut. $RESET"
		# Idem que traitements precedents, en plus simpliste. On considere l'absence de langue comme etant FRENCH
		SERIE=`echo ${i%.*} | sed -e 's/\(.*\)\.\([sS][0-9][0-9]\).*/\1/I' -e 's/\(.\)/\L\1/g' -e 's/\<./\u&/g'`;
		LANGUE="FRENCH";
		OUPS=1;
		SAISON=`echo ${i%.*} | sed -e 's/\(.*\)\.\([sS][0-9][0-9]\).*/\2/I' -e 's/\(.*\)/\U\1/g' -e 's/S/Saison./'`;
	fi

	# A partir des variables construites ci-dessus, on cree le chemin de destination du fichier sous la forme souhaitee
	# Adapter cette ligne à vos souhaits !
	#
	# Ici on construit un chemin sous la forme "LANGUE/SERIE/SAISON"
	#   Ex1 : FRENCH/Dexter/Saison.01
	#   Ex2 : VOSTFR/The.Walking.Dead/Saison.01
	#
	mkdir -p $REPO/$LANGUE/$SERIE/$SAISON
	
	
	# Maintenant que le dossier final est pret, on transfere le fichier
	#echo -e "  => Copying :$YELLOW $i$RESET to $GREEN$REPO/$LANGUE/$SERIE/$SAISON/$RESET.\n"
	if [ $OUPS == 0 ]
		then	printf "$RESET%15s $YELLOW%-70s $RESET%-5s $MAGENTA%s$RESET\n" "* Copying" "$i" "=>" "$REPO/$LANGUE/$SERIE/$SAISON/"
		else	printf "$RESET%15s $YELLOW%-70s $RESET%-5s $MAGENTA%s$RESET\n\n" "* Copying" "$i" "=>" "$REPO/$LANGUE/$SERIE/$SAISON/"
	fi
	/usr/bin/rsync -vtq -P --no-dirs --no-R $DEST/$i $REPO/$LANGUE/$SERIE/$SAISON
	OUPS=0;

done

find /tmp -name "dispatcher*" -mtime +7 -exec rm -rf {} \;


umask 0022

exit 0;
