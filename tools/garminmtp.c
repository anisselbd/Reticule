/*
 * garminmtp : liste GARMIN/Apps ou y copie un fichier, sur une montre Garmin en USB (MTP).
 *
 * Usage : garminmtp ls
 *         garminmtp put <fichier.prg>   (remplace un fichier du même nom déjà présent)
 *
 * Pourquoi un outil maison : libmtp 1.1.23 ne connaît pas la Forerunner 165 (091e:5150).
 * Avec ses réglages par défaut, mtp-folders et mtp-files tentent une lecture groupée des
 * propriétés que la montre ne gère pas, ce qui bloque sa session USB jusqu'au débranchement.
 * Ici, on force les réglages adaptés et on parcourt les dossiers un par un.
 *
 * Compilation : voir tools/installer-montre.sh
 */
#include <libmtp.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

/* Valeurs de device-flags.h (en-tête interne de libmtp, non installé) */
#define F_BROKEN_PROPLIST_ALL  0x00000001
#define F_UNLOAD_DRIVER        0x00000002
#define F_BROKEN_PROPLIST      0x00000004
#define F_BROKEN_SET_PROPLIST  0x00000100
#define F_BROKEN_SEND_PROPLIST 0x00008000
#define F_LONG_TIMEOUT         0x00100000

/* Parcourt un dossier. Renvoie l'id de l'entrée nommée `name` (dossier si `folder`, fichier sinon). */
static uint32_t find_child(LIBMTP_mtpdevice_t *d, uint32_t storage, uint32_t parent,
                           const char *name, int folder, int list) {
    uint32_t found = 0;
    LIBMTP_file_t *f = LIBMTP_Get_Files_And_Folders(d, storage, parent);
    while (f) {
        int is_folder = f->filetype == LIBMTP_FILETYPE_FOLDER;
        if (list) {
            printf("  %s%s  (%llu octets)\n", f->filename, is_folder ? "/" : "",
                   (unsigned long long)f->filesize);
        }
        if (name && !found && is_folder == folder && strcasecmp(f->filename, name) == 0) {
            found = f->item_id;
        }
        LIBMTP_file_t *next = f->next;
        LIBMTP_destroy_file_t(f);
        f = next;
    }
    return found;
}

static int put_file(LIBMTP_mtpdevice_t *d, uint32_t storage, uint32_t apps, const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) {
        perror(path);
        return 1;
    }
    char *copy = strdup(path);
    char *name = strdup(basename(copy));
    free(copy);

    uint32_t old = find_child(d, storage, apps, name, 0, 0);
    if (old) {
        printf("Remplacement de l'ancien %s\n", name);
        if (LIBMTP_Delete_Object(d, old) != 0) {
            fprintf(stderr, "Suppression de l'ancien fichier impossible\n");
            LIBMTP_Dump_Errorstack(d);
            free(name);
            return 1;
        }
    }

    LIBMTP_file_t *nf = LIBMTP_new_file_t();
    nf->filename = name; /* libéré par LIBMTP_destroy_file_t */
    nf->filesize = (uint64_t)st.st_size;
    nf->filetype = LIBMTP_FILETYPE_UNKNOWN;
    nf->parent_id = apps;
    nf->storage_id = storage;
    printf("Copie de %s (%lld octets)...\n", name, (long long)st.st_size);
    int r = LIBMTP_Send_File_From_File(d, path, nf, NULL, NULL);
    LIBMTP_destroy_file_t(nf);
    if (r != 0) {
        fprintf(stderr, "Échec de la copie\n");
        LIBMTP_Dump_Errorstack(d);
        return 1;
    }
    printf("Copie OK\n");
    return 0;
}

int main(int argc, char **argv) {
    int put = argc >= 3 && strcmp(argv[1], "put") == 0;
    if (!put && !(argc == 2 && strcmp(argv[1], "ls") == 0)) {
        fprintf(stderr, "usage : %s ls | put <fichier>\n", argv[0]);
        return 2;
    }

    LIBMTP_Init();
    LIBMTP_raw_device_t *raw = NULL;
    int count = 0;
    if (LIBMTP_Detect_Raw_Devices(&raw, &count) != LIBMTP_ERROR_NONE || count < 1) {
        fprintf(stderr, "Aucune montre détectée en USB (MTP). Est-elle branchée ?\n");
        return 1;
    }
    raw[0].device_entry.device_flags = F_BROKEN_PROPLIST_ALL | F_BROKEN_PROPLIST | F_UNLOAD_DRIVER |
                                       F_BROKEN_SET_PROPLIST | F_BROKEN_SEND_PROPLIST | F_LONG_TIMEOUT;
    LIBMTP_mtpdevice_t *d = LIBMTP_Open_Raw_Device_Uncached(&raw[0]);
    if (!d) {
        fprintf(stderr, "Connexion impossible. Débranchez la montre, attendez 5 s, rebranchez-la.\n");
        return 1;
    }
    char *model = LIBMTP_Get_Modelname(d);
    printf("Montre : %s\n", model ? model : "?");
    free(model);

    int rc = 1;
    if (LIBMTP_Get_Storage(d, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0 || !d->storage) {
        fprintf(stderr, "Stockage illisible\n");
        LIBMTP_Dump_Errorstack(d);
    } else {
        int found = 0;
        for (LIBMTP_devicestorage_t *s = d->storage; s; s = s->next) {
            uint32_t garmin = find_child(d, s->id, LIBMTP_FILES_AND_FOLDERS_ROOT, "GARMIN", 1, 0);
            uint32_t apps = garmin ? find_child(d, s->id, garmin, "Apps", 1, 0) : 0;
            if (!apps) {
                continue;
            }
            found = 1;
            rc = put ? put_file(d, s->id, apps, argv[2]) : 0;
            printf("GARMIN/Apps :\n");
            find_child(d, s->id, apps, NULL, 0, 1);
            break;
        }
        if (!found) {
            fprintf(stderr, "Dossier GARMIN/Apps introuvable\n");
        }
    }
    LIBMTP_Release_Device(d);
    return rc;
}
