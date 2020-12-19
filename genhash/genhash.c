/**
 *  Create an /etc/shadow -friendly SHA-512 hash from password + salt
 *  Copyright (C) 2020  xxc3nsoredxx
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main (int argc, char **argv) {
    /* crypt(3) allows up to 16 characters for a salt */
    char salt [17] = {0};
    char crypt_args [21] = {0};
    char *hashed;

    if (argc != 3) {
        printf("Usage: %s [password] [salt]\n", argv[0]);
        return -1;
    }

    /**
     * Convert the salt into the character set [a-zA-Z0-9./]
     * Invalid characters (if found) are replaced with '.'
     */
    strncpy(salt, argv[2], 16);
    for (int cx = 0; cx < strlen(salt); cx++) {
        if (!(salt[cx] >= 'a' && salt[cx] <= 'z')
            && !(salt[cx] >= 'A' && salt[cx] <= 'Z')
            && !(salt[cx] >= '0' && salt[cx] <= '9')
            && !(salt[cx] == '.' || salt[cx] == '/')) {
            salt[cx] = '.';
        }
    }

    sprintf(crypt_args, "$6$%s$", salt);
    hashed = crypt(argv[1], crypt_args);

    if (!hashed) {
        printf("Error!\n");
        return -1;
    }

    printf("%s\n", hashed);
    free(hashed);
}
